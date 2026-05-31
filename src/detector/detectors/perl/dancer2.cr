require "../../../models/detector"

module Detector::Perl
  class Dancer2 < Detector
    def detect(filename : String, file_contents : String) : Bool
      if dependency_manifest?(filename)
        return file_contents.includes?("Dancer2")
      end

      if perl_source?(filename)
        return file_contents.includes?("use Dancer2") ||
          file_contents.includes?("use Dancer2;") ||
          file_contents.includes?("Dancer2::Plugin") ||
          file_contents.includes?("Dancer2::Core") ||
          file_contents.includes?("extends 'Dancer2") ||
          file_contents.includes?("extends \"Dancer2") ||
          file_contents.includes?("use base 'Dancer2") ||
          file_contents.includes?("use base \"Dancer2") ||
          file_contents.includes?("parent 'Dancer2") ||
          file_contents.includes?("parent \"Dancer2")
      end

      false
    end

    def applicable?(filename : String) : Bool
      perl_source?(filename) || dependency_manifest?(filename)
    end

    def set_name
      @name = "perl_dancer2"
    end

    private def perl_source?(filename : String) : Bool
      filename.ends_with?(".pl") || filename.ends_with?(".pm") ||
        filename.ends_with?(".psgi") || filename.ends_with?(".t")
    end

    private def dependency_manifest?(filename : String) : Bool
      basename = File.basename(filename)
      basename == "cpanfile" ||
        basename == "cpanfile.snapshot" ||
        basename == "Makefile.PL" ||
        basename == "dist.ini" ||
        basename == "META.json" ||
        basename == "META.yml"
    end
  end
end
