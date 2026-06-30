/// Bundled SVG asset paths (ported from the Mynt Plus design set).
class Assets {
  Assets._();

  static const search = 'assets/icon/search.svg';
  static const bell = 'assets/icon/bell.svg';
  static const download = 'assets/icon/download.svg';

  static const myntLogo = 'assets/brand/mynt_logo.svg';
  static const zebuLogo = 'assets/brand/zebu_logo.svg';

  /// The brand logo used across splash / auth. Swap to [zebuLogo] for the
  /// Zebu corporate mark instead of the Mynt app logo.
  static const brandLogo = myntLogo;
}
