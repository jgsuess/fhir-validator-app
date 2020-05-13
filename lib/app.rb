# frozen_string_literal: true

require 'active_support/all'
require 'base64'
require 'sinatra'
require 'sinatra/base'
require 'sinatra/custom_logger'
require 'sinatra/namespace'
require 'pry'
require 'json'
require 'fhir_models'
require 'nokogiri'
Dir[File.join(__dir__, 'app', 'models', 'validators', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'app', 'models', 'util', '*.rb')].each { |file| require file }

module FHIRValidator
  # Top-level Sinatra app for the FHIR Validator webapp
  class App < Sinatra::Application
    set :views, settings.root + '/app/views'
    set :public_folder, (proc { File.join(settings.root, '..', 'public') })
    set :static, true

    l = ::Logger.new(STDOUT, level: 'info', progname: 'Inferno')
    l.formatter = proc do |severity, _datetime, progname, msg|
      "#{severity} | #{progname} | #{msg}\n"
    end
    FHIRValidator.logger = l

    # This class method gets used here in the route namespacing
    def self.base_path
      if ENV['validator_base_path']
        "/#{ENV['validator_base_path']}"
      else
        ''
      end
    end

    helpers do
      # This helper is used in templates to get the base path, for building URL paths
      def base_path
        App.base_path
      end
    end

    namespace base_path.to_s do
      get '/?' do
        @profiles = FHIRValidator::ValidationUtil.fhir_profiles
        erb :index
      end

      # Returns the static files associated with web app
      get '/static/*' do
        call! env.merge('PATH_INFO' => '/' + params['splat'].first)
      end

      get '/profiles' do
        content_type :json
        FHIRValidator::ValidationUtil.fhir_profiles.to_json
      end

      post '/validate' do
        # if params[:implementation_guide] == 'us_core'
        #   profile_url = "http://hl7.org/fhir/us/core/StructureDefinition/#{params[:profile]}"
        # end

        resource_blob = get_resource(params)
        @resource_type = Nokogiri::XML(resource_blob).errors.empty? ? 'xml' : 'json'

        @validator = HL7Validator.new

        if params[:profile].present?
          @profile_url = params[:profile]
        else
          profile = get_profile(params)
          @profile_url = @validator.add_profile(profile)
        end

        @results = @validator.validate(resource_blob, @resource_type, FHIR, @profile_url)
        @resource_string = Base64.encode64(resource_blob)

        erb :validate
      end
    end

    private

    def get_resource(params)
      resource_file = params.dig(:resource, :tempfile)
      resource_blob = params[:resource_field]
      if resource_file
        File.read(resource_file)
      else
        resource_blob
      end
    end

    def get_profile(params)
      profile_file = params.dig(:profile_file, :tempfile)
      profile_blob = params[:profile_field]
      if profile_file
        File.read(profile_file)
      else
        profile_blob
      end
    end
  end
end
