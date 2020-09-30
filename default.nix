let
  nixpkgs = import ./dep/nixpkgs { overlays = [overlay]; };

  nix-thunk = import ./dep/nix-thunk { pkgs = nixpkgs; };

  # Per thunk notes:
  #
  #  gitignore.nix: Not on nixpkgs: https://github.com/hercules-ci/gitignore.nix/issues/6
  #
  #  which: Hackage release (0.1.0.0) does not support GHC 8.8
  sources = nix-thunk.mapSubdirectories nix-thunk.thunkSource ./dep;

  gitignoreSource = (import sources."gitignore.nix" {}).gitignoreSource;

  overlay = self: super: {
    haskellPackages = with nixpkgs.haskell.lib;
      super.haskellPackages.override (old: {
        overrides = self: super: with nixpkgs.haskell.lib; {
          solana-bridges = overrideCabal (self.callCabal2nix "solana-bridges" (gitignoreSource ./solana-bridges) {}) (drv: {
            executableSystemDepends = (drv.executableSystemDepends or []) ++ (with nixpkgs; [ go-ethereum solc ]);
          });
          web3 = markUnbroken (doJailbreak (dontCheck super.web3));
          which = self.callCabal2nix "which" sources.which {};
        };
      });
  };

  solana = with nixpkgs; rustPlatform.buildRustPackage rec {
    pname = "solana";
    version = "v1.3.9";

    src = fetchFromGitHub {
      owner = "solana-labs";
      repo = pname;
      rev = version;
      sha256 = "0fxn2vdh7wkdh9zkl2y3dbprjs5w6mhnr6vp819537h39i2xw90n";
    };

    cargoSha256 = "0lmvixpkzgbkn9lj2w0c809yg5dgjpf8flmhwkk9jvx6dx9wzyqd";
    verifyCargoDeps = true;

    LIBCLANG_PATH="${llvmPackages.libclang}/lib";
    nativeBuildInputs = [ pkgconfig clang llvm ];
    buildInputs = [ libudev openssl ];
    strictDeps = true;

    # TODO: Either allow the nix build to increase file descriptor limit or patch out failing test
    #
    ## [2020-09-09T18:23:04.195996780Z ERROR solana_ledger::blockstore] Unable to increase the maximum open file descriptor limit to 500000
    ## test test_bench_tps_local_cluster_solana ... FAILED
    checkPhase = null;
  };

  solc = nixpkgs.solc.overrideAttrs (old: {
    # https://github.com/NixOS/nixpkgs/pull/97730
    checkPhase = null;
  });


  shell = nixpkgs.haskellPackages.shellFor {
    withHoogle = false; # https://github.com/NixOS/nixpkgs/issues/82245
    packages = p: [ p.solana-bridges ];
    nativeBuildInputs = [ solc ] ++ (with nixpkgs; [ cabal-install ghcid hlint go-ethereum solana ]);
  };

in {
  inherit nixpkgs shell solc;
  inherit (nixpkgs.haskellPackages) solana-bridges;
}
