Dummy::Application.routes.draw do
  get 'statics/show'
  resources :reports, only: :show
end
