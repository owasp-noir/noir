include "common/base.thrift"

struct SharedStruct {
  1: i32 key
  2: string value
}

service SharedService extends base.BaseService {
  SharedStruct getStruct(1: i32 key)
}
