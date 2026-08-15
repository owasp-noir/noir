require "../../../models/detector"

module Detector::Php
  class Phalcon < Detector
    detector_for "php_phalcon",
      extensions: %w[.php .phtml .ini],
      basenames: %w[composer.json composer.lock php.ini]

    # Phalcon ships as a compiled C extension (`pecl install phalcon`, or a
    # prebuilt `.so`/`.dll`), not a Composer dependency — there is no
    # `phalcon/cphalcon` package on Packagist for `composer.json` to name.
    # Real apps still declare the dependency in Composer via the standard
    # `ext-*` platform-package convention, and the community ships a
    # handful of auxiliary Composer packages alongside the extension:
    # IDE stubs (editor autocompletion against the compiled extension),
    # the incubator (community add-ons), devtools (code generators/CLI)
    # and migrations.
    PHALCON_PACKAGES = [
      "ext-phalcon",
      "phalcon/ide-stubs",
      "phalcon/incubator",
      "phalcon/devtools",
      "phalcon/migrations",
    ]

    # `extension=phalcon` (optionally `phalcon.so` / `phalcon.dll`) enabling
    # the compiled extension in `php.ini` — the way most real deployments
    # actually declare this dependency, since Composer has no package for
    # the extension itself.
    PHP_INI_EXTENSION_RE = /extension\s*=\s*["']?phalcon(?:\.(?:so|dll))?["']?/i

    # Every reference below is namespace-qualified under `Phalcon\`, which
    # no other PHP framework in this detector set spells. Unlike Laminas'
    # detector (which has to avoid the generic word "Zend"), a plain
    # substring match on the namespace is safe here.
    PHALCON_NAMESPACE_MARKERS = [
      "Phalcon\\Mvc\\Micro",
      "Phalcon\\Mvc\\Application",
      "Phalcon\\Mvc\\Controller",
      "Phalcon\\Mvc\\Router",
      "Phalcon\\Mvc\\Model",
      "Phalcon\\Di\\FactoryDefault",
      "Phalcon\\Di\\Di",
    ]

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      if basename == "composer.json" || basename == "composer.lock"
        return true if PHALCON_PACKAGES.any? { |package| file_contents.includes?(%("#{package}")) }
      end

      if basename == "php.ini" || filename.ends_with?(".ini")
        return true if file_contents.matches?(PHP_INI_EXTENSION_RE)
      end

      if filename.ends_with?(".php") || filename.ends_with?(".phtml")
        return true if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+Phalcon\\[^;\n]*;/)
        return true if PHALCON_NAMESPACE_MARKERS.any? { |marker| file_contents.includes?(marker) }
      end

      false
    end
  end
end
