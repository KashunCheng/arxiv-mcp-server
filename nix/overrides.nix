{ pkgs }:
final: prev: {
  sgmllib3k = prev.sgmllib3k.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      (final.resolveBuildSystem {
        setuptools = [ ];
        wheel = [ ];
      })
    ];
  });
}
