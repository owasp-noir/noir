require "../../models/detector"

class DetectorCrystalKemal < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("kemalcr/kemal")
    check = check && filename.includes?("shard.yml")

    set_base_path check, get_parent_path(filename)
    check
  end

  def set_name
    @name = "crystal_kemal"
  end
end
