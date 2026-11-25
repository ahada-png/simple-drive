# Never write blob contents or tokens to the logs.
Rails.application.config.filter_parameters += %i[data token secret passw]
