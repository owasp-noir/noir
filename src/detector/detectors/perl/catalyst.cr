require "../../../models/detector"

module Detector::Perl
  class Catalyst < Detector
    def detect(filename : String, file_contents : String) : Bool
      if dependency_manifest?(filename)
        return file_contents.includes?("Catalyst") ||
          file_contents.includes?("Catalyst::Runtime") ||
          file_contents.includes?("CatalystX::Routes") ||
          file_contents.includes?("Catalyst::Controller::REST")
      end

      if perl_source?(filename)
        return file_contents.includes?("use Catalyst") ||
          file_contents.includes?("extends 'Catalyst::Controller") ||
          file_contents.includes?("extends \"Catalyst::Controller") ||
          file_contents.includes?("use base 'Catalyst::Controller") ||
          file_contents.includes?("use base \"Catalyst::Controller") ||
          file_contents.includes?("parent 'Catalyst::Controller") ||
          file_contents.includes?("parent \"Catalyst::Controller") ||
          file_contents.includes?("Catalyst::Controller::REST") ||
          file_contents.includes?("CatalystX::Routes")
      end

      false
    end

    def applicable?(filename : String) : Bool
      perl_source?(filename) || dependency_manifest?(filename)
    end

    def set_name
      @name = "perl_catalyst"
    end

    private def perl_source?(filename : String) : Bool
      filename.ends_with?(".pl") || filename.ends_with?(".pm") ||
        filename.ends_with?(".psgi") || filename.ends_with?(".t")
    end

    private def dependency_manifest?(filename : String) : Bool
      basename = File.basename(filename)
      basename == "cpanfile" ||
        basename == "Makefile.PL" ||
        basename == "dist.ini" ||
        basename == "META.json" ||
        basename == "META.yml"
    end
  end
end
