# First, get RVM and Capistrano to play nice
set :rvm_type, :user
$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
require "rvm/capistrano"
set :rvm_ruby_string, 'ruby-1.9.2@my_gemset'

# User
#set :user, "user"

# This is defaulted to true - set it to false unless you really want root doing
# everything.
#set :use_sudo, false

# Options
ssh_options[:forward_agent] = true
default_run_options[:pty] = true

# Repo Info
set :repository, "git@github.com:my_github_account/my_repo.git"
set :branch, "master" # Set this to your branch of choice

# Application Info
set :application, "MyApplicationName"

# Version Control
set :scm, :git
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`
set :scm_verbose, true
set :scm_username, "my_user_name" # User name for github
set :scm_passphrase, "my_secret_password" # Password for the account above
set :scm_command, "/opt/local/bin/git" # Location of the git binary on the production machine

# Notes from help.github.com/capistrano
# Remote Cache In most cases you want to use this option, otherwise each deploy will do a full repository clone everytime
#set :deploy_via, :remote_cache
set :deploy_to, "/Users/user/apps/MyApplicationName" # Where should capistrano put things?

# Servers
role :web, "127.0.0.1"                          # Your HTTP server, Apache/etc
role :app, "127.0.0.1"                          # This may be the same as your `Web` server
role :db,  "127.0.0.1", :primary => true # This is where Rails migrations will run
#role :db,  "your slave db-server here"

# Bundler: run bundle install on the server
namespace :bundle do
  task :install, :roles => :app do
    run("cd #{current_release} && bundle install")
  end
end

after 'deploy:update', 'bundle:install' # run bundle install after updating the code base on production

namespace :deploy do

  # Start up unicorns - change this to your needs
  task :start do
    run("cd #{current_release} && unicorn_rails -c #{current_release}/config/unicorn/production_1.rb -l 127.0.0.1:8080 -E production -D")
  end

  # Stop unicorns - Here is an example where you don't have to rely on a pid file being around - though PID files are fine
  task :stop do
    run("kill -QUIT `ps -ef | grep unicorn | grep master | grep '127.0.0.1:8080' | awk '{print $2}'`")
  end

  task :restart do
    deploy.stop
    deploy.start
  end

  # start, stop and restart nginx under the deploy namespace - so:
  # cap deploy:nginx:restart - for example
  namespace :nginx do
    task :start do
      sudo("/usr/local/nginx/sbin/nginx -c #{current_release}/config/nginx/nginx.conf")
    end

    task :stop do
      sudo("kill  `ps -ef | grep 'nginx' | grep 'master' | awk '{pring $2}'`")
    end

    task :restart do
      nginx.stop
      nginx.start
    end
  end

  # Here is an example of how to do the hot deploy. To understand what's happening, please open up
  # nginx.conf and search for "upstream" - you'll see that traffic to nginx will be directed to the
  # new cluster of unicorn workers if the reroute.txt file exists. Then, we kill the original cluster - so
  # the steps are:
  # 1. Pull code from the repo
  # 2. Fire up a new cluster of unicorns on a different port and/or different socket name
  # 3. Create a reroute.txt file in the public/system folder
  # 4. Nginx sees reroute.txt and forwards all requests to the new cluster of unicorns running new code
  # 5. Shut down old cluster
  # 6. Bring up new cluster with the original, permanent settings
  # 7. remove the reroute.txt file
  # 8. kill the temporary cluster created in step 2.

  # NOTE: One could also set this up so that the reroute.txt is called either 8080_reroute.txt or 9090_reroute.txt
  # and nginx can be configured to route traffic to the appropriate socket depending on the reroute file - this would
  # make it so that you just fire up a new cluster of unicorns and switch to the new one and bring down the old one -
  # back and forth each time there is a deploy. Less steps.

  # cap deploy:hot
  task :hot do
    deploy.update
    commands = <<-SH
      cd #{current_release} && \
      unicorn_rails -c #{current_release}/config/unicorn/production_2.rb -l 127.0.0.1:9090 -E production -D && \
      echo "reroute" > #{current_release}/public/system/reroute.txt && \
      kill -QUIT `ps -ef | grep unicorn | grep master | grep "127.0.0.1:8080" | awk '{print $2}'` && \
      unicorn_rails -c #{current_release}/config/unicorn/production_1.rb -l 127.0.0.1:8080 -E production -D && \
      kill -QUIT `ps -ef | grep unicorn | grep master | grep "127.0.0.1:9090" | awk '{print $2}'` && \
      rm #{current_release}/public/system/reroute.txt
    SH
    run(commands)
  end
end
