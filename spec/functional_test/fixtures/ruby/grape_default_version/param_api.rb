module Twitter
  class ParamAPI < Grape::API
    version 'v3', :using => :param

    get :param_versioned do
      version = params[:version]
      version
    end
  end
end
