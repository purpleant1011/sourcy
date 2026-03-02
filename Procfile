# Procfile for Sourcy Application
# Using Solid Queue for background jobs, Solid Cache for caching, and Solid Cable for Action Cable

web: bundle exec rails server -p 3000
worker: bundle exec solid_queue start
cable: bundle exec solid_cable start
