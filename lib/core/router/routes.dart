/// Centralized route paths.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';

  static const dashboard = '/';
  static const tickets = '/tickets';
  static const tasks = '/tasks';
  static const more = '/more';

  static const notifications = '/notifications';
  static const faq = '/faq';
  static const canned = '/canned';
  static const reports = '/reports';
  static const agents = '/agents';
  static const tags = '/tags';
  static const team = '/team';
  static const profile = '/profile';
  static const serverSettings = '/settings/server';

  static const ticketNew = '/tickets/new';
  static const taskNew = '/tasks/new';

  /// Detail routes. [tab] pre-selects a tab on the detail screen —
  /// 'conversation' (the default), 'details' or 'activity'.
  static String ticket(int id, {String? tab}) =>
      tab == null ? '/tickets/$id' : '/tickets/$id?tab=$tab';
  static String task(int id, {String? tab}) =>
      tab == null ? '/tasks/$id' : '/tasks/$id?tab=$tab';
  static String faqArticle(int id) => '/faq/$id';
}
