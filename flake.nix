{
  description = "Pinapp - Desktop file editor for GNOME";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Build dependencies
        buildDeps = with pkgs; [
          meson
          ninja
          pkg-config
          wrapGAppsHook4
          gettext
          appstream-glib
          desktop-file-utils
          glib
        ];

        # Runtime dependencies
        runtimeDeps = with pkgs; [
          gtk4
          libadwaita
          glib
        ];

        pinapp = pkgs.stdenv.mkDerivation {
          pname = "pinapp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = buildDeps;
          buildInputs = runtimeDeps;

          # Compile gsettings schemas during build
          postInstall = ''
            glib-compile-schemas $out/share/glib-2.0/schemas
          '';
        };

      in {
        packages = {
          default = pinapp;
          pinapp = pinapp;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ pinapp ];

          # Additional dev tools
          packages = with pkgs; [
            zig
            clang-tools
            gdb
          ];

          # Environment variables for running uninstalled app
          shellHook = ''
            # Compile schemas if needed
            if [ ! -f "$PWD/data/gschemas.compiled" ]; then
              echo "Compiling gsettings schemas..."
              glib-compile-schemas "$PWD/data"
            fi

            export GSETTINGS_SCHEMA_DIR="$PWD/data"
            export XDG_DATA_DIRS="$PWD/data''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

            echo ""
            echo "Pinapp development environment"
            echo "  • Zig build: zig build (output: zig-out/bin/pinapp)"
            echo "  • Meson build: meson setup build && ninja -C build"
            echo "  • Run dev: zig build dev"
          '';
        };
      }
    );
}
