module example.com/app

go 1.22

require example.com/upstream/authlib v1.0.0

replace example.com/upstream/authlib => ../third_party/authlib
