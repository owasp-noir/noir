##
# This file mounts each app in the Padrino project to a specified sub-uri.
# Mounts the core application for this project at the root, and the admin
# sub-app under /admin.
Padrino.mount('core', app_class: 'CoreApp').to('/')
Padrino.mount('admin').to('/admin')
