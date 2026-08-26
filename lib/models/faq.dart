import '../core/api/json.dart';
import 'common.dart';

/// osTicket's `ispublished` — the three states the web's Listing Type select
/// writes (`FAQ::VISIBILITY_*`): 0 Internal, 1 Public, 2 Featured.
enum FaqListing {
  internal('Internal'),
  public('Public'),
  featured('Featured');

  const FaqListing(this.label);
  final String label;
}

/// A knowledgebase FAQ article. List rows carry less than the full article.
class Faq {
  const Faq({
    required this.id,
    required this.question,
    this.answer,
    this.published = false,
    this.type,
    this.category,
    this.attachments = const [],
    this.topicIds = const [],
    this.notes,
    this.created,
    this.updated,
  });

  final int id;
  final String question;
  final String? answer; // HTML (full only)
  final bool published;
  final String? type; // Internal | Public | Featured
  final NamedRef? category;
  final List<Attachment> attachments;

  /// Help topics this article answers. Served on both the list and the detail
  /// payloads, so a read round-trips straight into an edit.
  final List<int> topicIds;

  final String? notes;
  final DateTime? created;
  final DateTime? updated;

  /// The article's own listing type.
  ///
  /// Read from [type] — `FAQ::getVisibilityDescription()`, the only field that
  /// states all three — and falling back to [published] only when the server
  /// omits it. That order matters: [published] is `FAQ::isPublished()`, which
  /// is `ispublished != 0` **and the category is public**, so it reads false
  /// for a Public article filed under a Private category, and it cannot say
  /// Featured at all. Writing it back from that boolean would demote the
  /// article's own column.
  FaqListing get listing {
    switch (type?.trim().toLowerCase()) {
      case 'featured':
        return FaqListing.featured;
      case 'public':
        return FaqListing.public;
      case 'internal':
      case 'private':
        return FaqListing.internal;
    }
    return published ? FaqListing.public : FaqListing.internal;
  }

  factory Faq.fromJson(Map<String, dynamic> j) => Faq(
    id: J.intOr(j['id']),
    question: J.strOr(j['question']),
    answer: J.str(j['answer']),
    published: J.boolOr(j['published']),
    type: J.str(j['type']),
    category: NamedRef.maybe(j['category']),
    attachments: J.mapList(j['attachments']).map(Attachment.fromJson).toList(),
    topicIds: J.list(j['topic_ids']).map((e) => J.intOr(e)).toList(),
    notes: J.str(j['notes']),
    created: J.dateTime(j['created']),
    updated: J.dateTime(j['updated']),
  );
}

/// A KB category. The detail variant embeds its [faqs].
class FaqCategory {
  const FaqCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.fullName,
    this.public = false,
    this.type,
    this.faqCount = 0,
    this.faqs = const [],
  });

  final int id;

  /// The category's own (local) name — "Pay in".
  final String name;

  /// Parent category, `0` for a top-level one. Null when unpublished.
  final int? parentId;

  /// The parent path the web's Categories list renders via `getFullName()` —
  /// "Funds / Pay in". Null when unpublished; use [displayName].
  final String? fullName;

  final bool public;
  final String? type; // Private | Public | Featured
  final int faqCount;
  final List<Faq> faqs;

  /// What to put on the row: the parent path when the server states one,
  /// otherwise the local name.
  String get displayName {
    final full = fullName?.trim() ?? '';
    return full.isEmpty ? name : full;
  }

  factory FaqCategory.fromJson(Map<String, dynamic> j) => FaqCategory(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    parentId: J.intOrNull(j['pid']),
    fullName: J.strNonBlank(j['full_name']),
    public: J.boolOr(j['public']),
    type: J.str(j['type']),
    faqCount: J.intOr(j['faq_count']),
    faqs: J.mapList(j['faqs']).map(Faq.fromJson).toList(),
  );
}
