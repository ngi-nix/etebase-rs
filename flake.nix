{
  description = "A Rust library for Etebase";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-21.05";

  inputs.import-cargo.url = github:edolstra/import-cargo;

  outputs = { self, nixpkgs, import-cargo }:
    let

      # Generate a user-friendly version numer.
      version = builtins.substring 0 8 self.lastModifiedDate;

      # System types to support.
      supportedSystems = [ "x86_64-linux" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

    in {

      # A Nixpkgs overlay.
      overlay = final: prev: {
        
        etebase-rs = with final; final.callPackage ({ inShell ? false }: stdenv.mkDerivation rec {
          name = "etebase-rs-${version}";
          
          # In 'nix develop', we don't need a copy of the source tree
          # in the Nix store.
          src = if inShell then null else ./.;
          
          buildInputs =
            [ rustc
              cargo
              openssl
              pkg-config
              libsodium
            ] ++ (if inShell then [
              # In 'nix develop', provide some developer tools.
              rustfmt
              clippy
            ] else [
              (import-cargo.builders.importCargo {
                lockFile = ./Cargo.lock;
                inherit pkgs;
              }).cargoHome
            ]);
          
          nativeBuildInputs = [ pkg-config libsodium ];
          
          buildPhase =
            ''
              export SODIUM_USE_PKG_CONFIG=1
              export OPENSSL_DIR="${pkgs.openssl.dev}"
              export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
            '';
          
          installPhase =
            ''
              mkdir -p $out
              cargo build --frozen --offline --out-dir $out -Z unstable-options 
            '';
        }) {};
        
      };
      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) etebase-rs;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.etebase-rs);

      # Provide a 'nix develop' environment for interactive hacking.
      devShell = forAllSystems (system: self.packages.${system}.etebase-rs.override { inShell = true; });

    };
}
