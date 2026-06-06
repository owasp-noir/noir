require "../../../models/detector"

module Detector::Perl
  class Mojolicious < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Dependency manifests
      if filename.ends_with?("cpanfile") ||
         filename.ends_with?("Makefile.PL") ||
         filename.ends_with?("dist.ini") ||
         filename.ends_with?("META.json") ||
         filename.ends_with?("META.yml")
        return file_contents.includes?("Mojolicious")
      end

      # Source files
      if filename.ends_with?(".pl") || filename.ends_with?(".pm") ||
         filename.ends_with?(".psgi") || filename.ends_with?(".t")
        return file_contents.includes?("use Mojolicious::Lite") ||
          file_contents.includes?("Mojolicious::Lite") ||
          file_contents.includes?("Mojo::Base 'Mojolicious") ||
          file_contents.includes?("Mojo::Base \"Mojolicious") ||
          file_contents.includes?("use Mojolicious")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".pl") || filename.ends_with?(".pm") || filename.ends_with?(".psgi") || filename.ends_with?(".t") || File.basename(filename) == "cpanfile" || File.basename(filename) == "Makefile.PL" || File.basename(filename) == "dist.ini" || File.basename(filename) == "META.json" || File.basename(filename) == "META.yml"
    end

    def set_name
      @name = "perl_mojolicious"
    end
  end
end
