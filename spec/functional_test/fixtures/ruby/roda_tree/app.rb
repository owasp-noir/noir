class App < Roda
  plugin :rodauth do
    enable :login, :logout
  end

  route do |r|
    r.rodauth
    rodauth.require_authentication

    r.root do
      'home'
    end

    r.is 'profile' do
      r.get do
        'p'
      end
    end

    r.on 'settings' do
      r.get 'email' do
        'email'
      end
      r.get 'password' do
        'password'
      end
      r.get 'tokens' do
        'tokens'
      end
    end

    r.on 'reports' do
      r.on 'income' do
        r.get true do
          'all'
        end
        r.get Integer do |year|
          'year'
        end
      end
      r.get 'entry', [Integer, true] do |id|
        r.params['q']
      end
    end
  end
end
