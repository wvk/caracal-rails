Dummy::Application.routes.draw do
  get 'statics/show'
  resources :reports, only: :show

  resources :monthly_reports, only: :show do
    member do
      get :preview
      get :cover
    end
  end
end
