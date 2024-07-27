{
  lib,
  fetchurl,
  stdenvNoCC,
  fetchYarnDeps,
  mkYarnPackage,
  makeWrapper,
  copyDesktopItems,
  fetchFromGitHub,
  buildGoModule,
  breakpointHook,
  electron-bin,
  makeDesktopItem,
}: let
  pname = "waveterm";
  info = lib.importJSON ./info.json;
  genMeta = tag-version: {
    changelog = "https://github.com/wavetermdev/waveterm/releases/tag/v${tag-version}";
    description = "An Open-Source, AI-Native, Terminal Built for Seamless Workflows";
    homepage = "https://github.com/wavetermdev/wavetermn";
    license = lib.licenses.asl20;
    mainProgram = pname;
    platforms = lib.platforms.unix;
  };

  darwin = let
    version = info.darwin.version;
  in
    stdenvNoCC.mkDerivation (
      finalAttrs: {
        inherit pname version;
        meta = genMeta version;

        src = fetchurl {
          inherit (info.darwin) hash;
          url = "https://dl.waveterm.dev/releases/Wave-darwin-universal-${version}.dmg";
        };

        sourceRoot = ".";

        unpackPhase = ''
          runHook preUnpack

          # Since the .dmg is using APFS we can't use undmg.
          # I also tried to use _7zz but it corrupts the .app.
          /usr/bin/hdiutil attach $src
          cp -r "/Volumes/Wave ${version}-universal/Wave.app" .
          /usr/bin/hdiutil detach "/Volumes/Wave ${version}-universal"

          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/Applications
          cp -r *.app $out/Applications
          chmod +x $out/Applications/*.app

          runHook postInstall
        '';
      }
    );

  linux = let
    version = info.linux.version;
    src = fetchFromGitHub {
      owner = "wavetermdev";
      repo = pname;
      rev = "v${version}";
      sha256 = info.linux.hash;
    };
    wavesrv = buildGoModule {
      inherit version src;
      preBuild = ''
        # go: 'go mod vendor' cannot be run in workspace mode. Run 'go work vendor' to vendor the workspace or set 'GOWORK=off' to exit workspace mode.
        # https://github.com/NixOS/nixpkgs/issues/203039
        export GOWORK="off";
      '';
      pname = "${pname}-wavesrv";
      modRoot = "./wavesrv";
      vendorHash = "";
      doCheck = false; # Currently fails at comp_test.go:91: comp-fail: ls f[*] + [foo bar] => [ls foo\ bar [*]] expected[ls 'foo bar' [*]]
    };
    waveshell = buildGoModule {
      inherit version src;
      preBuild = ''
        # go: 'go mod vendor' cannot be run in workspace mode. Run 'go work vendor' to vendor the workspace or set 'GOWORK=off' to exit workspace mode.
        # https://github.com/NixOS/nixpkgs/issues/203039
        export GOWORK="off";
      '';
      pname = "${pname}-waveshell";
      modRoot = "./waveshell";
      vendorHash = "";
    };
    electron = electron-bin;
  in
    mkYarnPackage rec {
      inherit pname src version;
      meta = genMeta version;

      packageJSON = "${src}/package.json";

      env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

      offlineCache = fetchYarnDeps {
        yarnLock = "${src}/yarn.lock";
        hash = "";
      };

      nativeBuildInputs = [
        makeWrapper
        copyDesktopItems
        breakpointHook
      ];

      buildPhase = ''
        runHook preBuild

        pushd deps/${pname}
        node_modules/.bin/webpack --env prod
        popd

        runHook postBuild
      '';

      postBuild = ''
        pushd deps/${pname}

        mkdir ./bin
        cp ${wavesrv}/bin/cmd ./bin/wavesrv.amd64
        mkdir ./bin/mshell
        cp ${waveshell}/bin/waveshell ./bin/mshell/mshell-v0.6-linux.amd64

        yarn --offline run electron-builder \
          --dir \
          -l \
          -p never \
          -c electron-builder.config.js \
          -c.electronDist=${electron}/libexec/electron \
          -c.electronVersion=${electron.version}

        popd
      '';

      installPhase = ''
        runHook preInstall

        # resources
        mkdir -p "$out/share/lib/${pname}"
        cp -r ./deps/${pname}/make/*-unpacked/{locales,resources{,.pak}} "$out/share/lib/${pname}"

        # icons
        #install -Dm644 ./deps/${pname}/static/Icon.png $out/share/icons/hicolor/1024x1024/apps/${pname}.png

        # executable wrapper
        makeWrapper '${electron}/bin/electron' "$out/bin/${pname}" \
          --add-flags "$out/share/lib/${pname}/resources/app.asar" \
          --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}" \
          --inherit-argv0

        runHook postInstall
      '';
      # Do not attempt generating a tarball for contents again.
      # note: `doDist = false;` does not work.
      distPhase = "true";

      desktopItems = [
        (makeDesktopItem {
          name = pname;
          exec = pname;
          icon = pname;
          desktopName = "Wave Terminal";
          genericName = "waveterm";
          comment = meta.description;
          categories = ["System"];
          startupWMClass = pname;
        })
      ];
    };
in
  if stdenvNoCC.isDarwin
  then darwin
  else linux
