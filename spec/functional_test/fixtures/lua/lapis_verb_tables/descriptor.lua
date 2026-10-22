-- Descriptor form: the route entry carries a schema alongside the verb
-- table, so the methods live one level down under `methods`.
local kong = kong

return {
  ["/clustering/data-planes"] = {
    schema = kong.db.clustering_data_planes.schema,
    methods = {
      GET = function(self, dao, helpers)
        return dao.clustering_data_planes:page()
      end,
    },
  },
}
