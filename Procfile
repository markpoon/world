web: bundle exec rackup -R config.ru -p $PORT
worker: bundle exec sidekiq -r ./app.rb -C config/sidekiq.yml