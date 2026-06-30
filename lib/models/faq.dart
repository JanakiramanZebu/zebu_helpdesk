import '../core/api/json.dart';
import 'common.dart';

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
  final String? notes;
  final DateTime? created;
  final DateTime? updated;

  factory Faq.fromJson(Map<String, dynamic> j) => Faq(
    id: J.intOr(j['id']),
    question: J.strOr(j['question']),
    answer: J.str(j['answer']),
    published: J.boolOr(j['published']),
    type: J.str(j['type']),
    category: NamedRef.maybe(j['category']),
    attachments: J.mapList(j['attachments']).map(Attachment.fromJson).toList(),
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
    this.public = false,
    this.type,
    this.faqCount = 0,
    this.faqs = const [],
  });

  final int id;
  final String name;
  final bool public;
  final String? type; // Private | Public | Featured
  final int faqCount;
  final List<Faq> faqs;

  factory FaqCategory.fromJson(Map<String, dynamic> j) => FaqCategory(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    public: J.boolOr(j['public']),
    type: J.str(j['type']),
    faqCount: J.intOr(j['faq_count']),
    faqs: J.mapList(j['faqs']).map(Faq.fromJson).toList(),
  );
}
