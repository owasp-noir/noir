from flask_appbuilder.api import ModelRestApi, expose


class BaseResourceApi(ModelRestApi):
    @expose("/related/<column_name>", methods=("GET",))
    def related(self, column_name):
        return self.response(200)

    @expose("/distinct/<column_name>", methods=("GET",))
    def distinct(self, column_name):
        return self.response(200)
