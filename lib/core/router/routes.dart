/// Centralized route paths.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';

  static const dashboard = '/';
  static const tickets = '/tickets';
  static const tasks = '/tasks';
  static const more = '/more';

  static const notifications = '/notifications';
  static const users = '/users';
  static const organizations = '/organizations';
  static const faq = '/faq';
  static const canned = '/canned';
  static const queues = '/queues';
  static const reports = '/reports';
  static const profile = '/profile';

  static const ticketNew = '/tickets/new';
  static const taskNew = '/tasks/new';

  static String ticket(int id) => '/tickets/$id';
  static String task(int id) => '/tasks/$id';
  static String user(int id) => '/users/$id';
  static String organization(int id) => '/organizations/$id';
  static String faqArticle(int id) => '/faq/$id';
}
