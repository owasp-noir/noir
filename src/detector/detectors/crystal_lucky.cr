require "../../models/detector"

class DetectorCrystalLucky < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = file_contents.includes?("luckyframework/lucky")
    check = check && filename.includes?("shard.yml")

    check
  end

  def set_name
    @name = "crystal_lucky"
  end
end
