class API < Grape::API
  resource :tasks do
    desc 'List the things to do'
    get do
      Task.all
    end
  end

  resource :users do
    get :me do
      error!('You cannot do that', 403) unless current_user
      current_user
    end
  end

  resource :items do
    params do
      requires :id, type: Integer, desc: 'The item'
      optional :mode, type: String, desc: 'What to do with the item'
    end
    post :archive do
      Item.find(params[:id]).archive!(params[:mode])
    end

    get :recent do
      Item.recent
    end
  end

  resource :reports do
    get do
      rows = Report.all.map do |r|
        r.title
      end.compact
      present rows
    end
  end

  resource :exports do
    get do
      Export.all.map do |e|
        e
      end.each do |e|
        e.touch
      end
    end
  end

  get :health do
    'ok'
  end
end
