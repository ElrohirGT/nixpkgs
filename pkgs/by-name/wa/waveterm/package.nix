{
  lib,
  fetchurl,
  stdenvNoCC,
}: let
  pname = "waveterm";
  info = lib.importJSON ./info.json;
  meta = tag-version: {
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
        meta = meta version;

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
in
  darwin
