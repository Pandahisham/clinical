require "ruby-debug"

module Clinical
  class Trial
    include HappyMapper
    include HTTParty

    base_uri "http://clinicaltrials.gov"
    default_params :displayxml => true 

    tag "clinical_study"
    element :nct_id, String, :deep => true
    element :read_status, Clinical::Status, :tag => "status", :parser => :parse
    element :overall_status, Clinical::Status, :parser => :parse
    element :url, String    
    element :short_title, String, :tag => "title"
    element :official_title, String
    element :condition_summary, String
    has_many :condition_items, String, :tag => "condition"
    element :phase, String
    element :study_type, String

    element :lead_sponsor, String, :tag => "sponsors/lead_sponsor"
    has_many :collaborators, String, :tag => "sponsors/collaborator"
    has_many :agencies, String, :tag => "sponsors/agency"

    has_many :interventions, Intervention, :tag => "intervention"
    has_many :primary_outcomes, PrimaryOutcome
    has_many :secondary_outcomes, SecondaryOutcome

    element :start_date, Date
    element :last_changed_at, Date, :tag => "lastchanged_date"

    element :minimum_age, String
    element :maximum_age, String
    element :gender, String
    element :healthy_volunteers, String

    element :url, String, :tag => "required_header/url"
    element :eligibility_criteria, String, :tag => "eligibility/criteria/textblock"

    element :brief_summary, String, :tag => "brief_summary/textblock"
    element :detailed_description, String, :tag => "brief_summary/textblock"

    def id
      self.nct_id
    end

    def open?
      self.status && self.status.open?
    end

    def sponsors
      @sponsors ||= [lead_sponsor, (collaborators || []), (agencies || [])].flatten
    end

    def outcomes
      @outcomes ||= [primary_outcomes, secondary_outcomes].flatten
    end

    def status
      self.read_status || self.overall_status
    end

    def conditions
      if condition_items.nil? || condition_items.empty?
        condition_summary.split(";")
      else
        condition_items
      end
    end

    class << self
      def find_by_id(id)
        response = get("/show/#{id}")
        if response.code == 400
          nil
        else
          begin
            parse(response.body)
          rescue LibXML::XML::Error
            return nil
          end 
        end
      end

      def find(*args)
        options = args.extract_options!

        options[:page] ||= 1
        options[:per_page] ||= 20

        query = query_hash_for(*[args, options])
        response = get("/search", :query => query)
        trials = Collection.create_from_results(options[:page], 
          options[:per_page], 
          response.body)

        if options[:extended]
          fetch_more_details(trials)
        else
          trials
        end
      end

      def query_hash_for(*args)
        query = {}
        options = args.extract_options! || {}
        
        conditions = options[:conditions] || {}
        query["start"] = (options[:per_page] * options[:page]) - (options[:per_page] - 1)
        unless conditions[:recruiting].nil?
          query["recr"] = conditions[:recruiting] ? "open" : "closed" 
        end
        query["term"] = args.first if args.first.is_a?(String)
        
        {
          :condition => "cond", 
          :sponsor => "spons",
          :intervention => "intr",
          :outcome => "outc",
          :sponsor => "spons"
        }.each do |key,value|
          query[value] = conditions[key] unless conditions[key].nil?
        end

        query
      end

      def extract_options!
        last.is_a?(Hash) ? pop : { }
      end
      
      private
      def fetch_more_details(trials)
        detailed_trials = trials.collect {|i| find_by_id(i.id)}
        Collection.create(trials.current_page, trials.per_page, trials.count || 0) do |pager|
          pager.replace(detailed_trials)
        end
      end
    end
  end
end
