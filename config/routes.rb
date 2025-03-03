require 'sidekiq/web'


Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  root to: "index#welcome"

  get 'ticker' => "live#ticker"

  mount Sidekiq::Web => '/sidekiq'

end
