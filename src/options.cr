def default_options
  noir_options = {
    :base => "", :url => "", :format => "plain",
    :output => "", :techs => "", :debug => "no", :color => "yes",
    :send_proxy => "", :send_req => "no",
    :scope => "url,param", :set_pvalue => "", :nolog => "no",
  }

  noir_options
end
