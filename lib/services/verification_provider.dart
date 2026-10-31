/// A deliberately manual verification boundary. This app does not scrape or
/// submit the BMDC site; an authorised admin records the outcome after their
/// own review of the registry.
abstract interface class VerificationProvider {
  const VerificationProvider();

  String get id;

  ManualVerificationResult recordOutcome({
    required String registrationNumber,
    required BmdcVerificationOutcome outcome,
  });
}

enum BmdcVerificationOutcome { found, notFound, mismatch }

extension BmdcVerificationOutcomeLabel on BmdcVerificationOutcome {
  String get value => switch (this) {
        BmdcVerificationOutcome.found => 'found',
        BmdcVerificationOutcome.notFound => 'not_found',
        BmdcVerificationOutcome.mismatch => 'mismatch',
      };

  String get label => switch (this) {
        BmdcVerificationOutcome.found => 'Found',
        BmdcVerificationOutcome.notFound => 'Not found',
        BmdcVerificationOutcome.mismatch => 'Mismatch',
      };
}

class ManualVerificationResult {
  const ManualVerificationResult({
    required this.registrationNumber,
    required this.outcome,
  });

  final String registrationNumber;
  final BmdcVerificationOutcome outcome;
}

class ManualVerificationProvider implements VerificationProvider {
  const ManualVerificationProvider();

  @override
  String get id => 'manual';

  @override
  ManualVerificationResult recordOutcome({
    required String registrationNumber,
    required BmdcVerificationOutcome outcome,
  }) {
    return ManualVerificationResult(
      registrationNumber: registrationNumber.trim(),
      outcome: outcome,
    );
  }
}
