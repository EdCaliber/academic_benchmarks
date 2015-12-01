require 'active_support/hash_with_indifferent_access'

require_relative 'auth'
require_relative 'constants'

module AcademicBenchmarks
  module Api
    class Standards
      DEFAULT_PER_PAGE = 100

      def initialize(handle)
        @handle = handle
      end

      def search(opts = {})
        # query: "", authority: "", subject: "", grade: "", subject_doc: "", course: "",
        # document: "", parent: "", deepest: "", limit: -1, offset: -1, list: "", fields: []
        invalid_params = invalid_search_params(opts)
        if invalid_params.empty?
          raw_search(opts).map do |standard|
            AcademicBenchmarks::Standards::Standard.new(standard)
          end
        else
          raise ArgumentError.new(
            "Invalid search params: #{invalid_params.join(', ')}"
          )
        end
      end

      alias_method :where, :search

      def guid(guid, fields: [])
        query_params = if fields.empty?
                         auth_query_params
                       else
                         auth_query_params.merge({
                           fields: fields.join(",")
                         })
                       end
        @handle.class.get(
          "/standards/#{guid}",
          query: query_params
        ).parsed_response["resources"].map do |r|
          AcademicBenchmarks::Standards::Standard.new(r["data"])
        end
      end

      def all
        request_search_pages_and_concat_resources(auth_query_params)
      end

      def authorities
        raw_search(list: "authority").map{|a| a["data"]["authority"]}.map{|a| AcademicBenchmarks::Standards::Authority.from_hash(a)}
      end

      private

      def raw_search(opts = {})
        request_search_pages_and_concat_resources(opts.merge(auth_query_params))
      end

      def invalid_search_params(opts)
        opts.keys.map(&:to_s) - AcademicBenchmarks::Api::Constants.standards_search_params
      end

      def auth_query_params
        AcademicBenchmarks::Api::Auth.auth_query_params(
          partner_id: @handle.partner_id,
          partner_key: @handle.partner_key,
          expires: AcademicBenchmarks::Api::Auth.expire_time_in_2_hours,
          user_id: @handle.user_id
        )
      end

      def request_search_pages_and_concat_resources(query_params)
        query_params.reverse_merge!({limit: DEFAULT_PER_PAGE})

        if !query_params[:limit] || query_params[:limit] <= 0
          raise ArgumentError.new(
            "limit must be specified as a positive integer"
          )
        end

        first_page = request_page(
          query_params: query_params,
          limit: query_params[:limit],
          offset: 0
        ).parsed_response

        resources = first_page["resources"]
        count = first_page["count"]
        offset = query_params[:limit]

        while offset < count
          page = request_page(
            query_params: query_params,
            limit: query_params[:limit],
            offset: offset
          )
          offset += query_params[:limit]
          resources.push(page.parsed_response["resources"])
        end

        resources.flatten
      end

      def request_page(query_params:, limit:, offset:)
        query_params.merge!({
          limit: limit,
          offset: offset,
        })
        resp = @handle.class.get(
          '/standards',
          query: query_params.merge({
            limit: limit,
            offset: offset,
          })
        )
        if resp.code != 200
          raise RuntimeError.new(
            "Received response '#{resp.code}: #{resp.message}' requesting standards from Academic Benchmarks:"
          )
        end
        resp
      end
    end
  end
end