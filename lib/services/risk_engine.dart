// Replace old DomainIntelligence.analyze(url) with:
import 'domain_intelligence/domain_intelligence.dart';

final domainReport = await DomainIntelligence.analyze(message);

// domainReport.highestScore      → int 0-100
// domainReport.results[0].domain → final domain after redirects
// domainReport.results[0].indicators → full explanation list
// domainReport.results[0].registrar  → "GoDaddy LLC", "Namecheap Inc"...
// domainReport.results[0].domainAge  → "3 days old"
// domainReport.results[0].ipAddresses → ["104.21.x.x", ...]
// domainReport.results[0].nameservers → ["ns1.freenom.com", ...]
