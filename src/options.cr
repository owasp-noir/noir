def default_options
  noir_options = {
    :base => "", :url => "", :format => "plain",
    :output => "", :techs => "", :debug => "no", :color => "yes", :concurrency => "100", :include_path => "no",
    :send_proxy => "", :send_req => "no", :send_with_headers => "", :send_es => "", :use_matchers => "", :use_filters => "",
    :set_pvalue => "", :nolog => "no",
    :exclude_techs => "",
  }

  noir_options
end
