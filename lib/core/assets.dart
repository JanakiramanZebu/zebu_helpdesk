/// Bundled SVG asset paths (ported from the Mynt Plus design set).
class Assets {
  Assets._();

  static const search = 'assets/icon/search.svg';
  static const bell = 'assets/icon/bell.svg';
  static const download = 'assets/icon/download.svg';
  static const claim = 'assets/icon/claim.svg';

  // Bottom-navigation glyphs (custom line set).
  static const navDashboard = 'assets/icon/nav_dashboard.svg';
  static const navTickets = 'assets/icon/nav_tickets.svg';
  static const navTasks = 'assets/icon/nav_tasks.svg';
  static const navInbox = 'assets/icon/nav_inbox.svg';
  static const navMore = 'assets/icon/nav_more.svg';

  // Menu ("More" tab) tile glyphs (custom line set).
  static const menuInbox = 'assets/icon/menu_inbox.svg';
  static const menuUsers = 'assets/icon/menu_users.svg';
  static const menuOrgs = 'assets/icon/menu_orgs.svg';
  static const menuReports = 'assets/icon/menu_reports.svg';
  static const menuKnowledge = 'assets/icon/menu_knowledge.svg';
  static const menuCanned = 'assets/icon/menu_canned.svg';
  static const menuQueues = 'assets/icon/menu_queues.svg';

  // Profile screen row-action glyphs (custom line set).
  static const profileAvailable = 'assets/icon/profile_available.svg';
  static const profileEdit = 'assets/icon/profile_edit.svg';
  static const profilePassword = 'assets/icon/profile_password.svg';
  static const profileAvatar = 'assets/icon/profile_avatar.svg';

  static const myntLogo = 'assets/brand/mynt_logo.svg';
  static const zebuLogo = 'assets/brand/zebu_logo.svg';

  /// The brand logo used across splash / auth. Swap to [zebuLogo] for the
  /// Zebu corporate mark instead of the Mynt app logo.
  static const brandLogo = myntLogo;
}
