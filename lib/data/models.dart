import '../core/formatters.dart';

typedef Json = Map<String, dynamic>;

class CompanyMembership {
  CompanyMembership({
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.currency,
  });

  final String companyId;
  final String companyName;
  final String role;
  final String currency;

  factory CompanyMembership.fromJson(Json json) {
    final company = (json['companies'] as Map?)?.cast<String, dynamic>() ?? {};
    return CompanyMembership(
      companyId: json['company_id'].toString(),
      companyName: company['name']?.toString() ?? 'Company',
      role: json['role']?.toString() ?? 'viewer',
      currency: company['currency']?.toString() ?? 'GBP',
    );
  }
}

class Vehicle {
  Vehicle({
    required this.id,
    required this.companyId,
    required this.registration,
    required this.mileage,
    required this.status,
    required this.inspectionType,
    required this.isActive,
    this.currentDriverId,
    this.currentDriverName,
    this.vin,
    this.make,
    this.model,
    this.year,
    this.inspectionDueDate,
    this.serviceDueDate,
    this.serviceDueMileage,
    this.insuranceExpiryDate,
    this.notes,
  });

  final String id;
  final String companyId;
  final String? currentDriverId;
  final String? currentDriverName;
  final String registration;
  final String? vin;
  final String? make;
  final String? model;
  final int? year;
  final int mileage;
  final String status;
  final String inspectionType;
  final DateTime? inspectionDueDate;
  final DateTime? serviceDueDate;
  final int? serviceDueMileage;
  final DateTime? insuranceExpiryDate;
  final String? notes;
  final bool isActive;

  factory Vehicle.fromJson(Json json) {
    final driver = (json['drivers'] as Map?)?.cast<String, dynamic>();
    return Vehicle(
      id: json['id'].toString(),
      companyId: json['company_id'].toString(),
      currentDriverId: json['current_driver_id']?.toString(),
      currentDriverName: driver?['name']?.toString(),
      registration: json['registration']?.toString() ?? '',
      vin: json['vin']?.toString(),
      make: json['make']?.toString(),
      model: json['model']?.toString(),
      year: (json['year'] as num?)?.toInt(),
      mileage: (json['mileage'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'available',
      inspectionType: json['inspection_type']?.toString() ?? 'MOT',
      inspectionDueDate: parseDate(json['inspection_due_date']),
      serviceDueDate: parseDate(json['service_due_date']),
      serviceDueMileage: (json['service_due_mileage'] as num?)?.toInt(),
      insuranceExpiryDate: parseDate(json['insurance_expiry_date']),
      notes: json['notes']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class Driver {
  Driver({
    required this.id,
    required this.companyId,
    required this.name,
    required this.status,
    required this.isActive,
    this.userId,
    this.phone,
    this.email,
    this.employeeReference,
    this.notes,
  });

  final String id;
  final String companyId;
  final String? userId;
  final String name;
  final String? phone;
  final String? email;
  final String? employeeReference;
  final String status;
  final String? notes;
  final bool isActive;

  factory Driver.fromJson(Json json) => Driver(
        id: json['id'].toString(),
        companyId: json['company_id'].toString(),
        userId: json['user_id']?.toString(),
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        employeeReference: json['employee_reference']?.toString(),
        status: json['status']?.toString() ?? 'active',
        notes: json['notes']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

class Garage {
  Garage({
    required this.id,
    required this.companyId,
    required this.name,
    required this.isActive,
    this.contactName,
    this.phone,
    this.email,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.postcode,
    this.country,
    this.notes,
  });

  final String id;
  final String companyId;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postcode;
  final String? country;
  final String? notes;
  final bool isActive;

  factory Garage.fromJson(Json json) => Garage(
        id: json['id'].toString(),
        companyId: json['company_id'].toString(),
        name: json['name']?.toString() ?? '',
        contactName: json['contact_name']?.toString(),
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        addressLine1: json['address_line_1']?.toString(),
        addressLine2: json['address_line_2']?.toString(),
        city: json['city']?.toString(),
        postcode: json['postcode']?.toString(),
        country: json['country']?.toString(),
        notes: json['notes']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

class FleetIssue {
  FleetIssue({
    required this.id,
    required this.companyId,
    required this.vehicleId,
    required this.title,
    required this.priority,
    required this.status,
    required this.reportedAt,
    this.registration,
    this.reportedByDriverId,
    this.description,
    this.mileageAtReport,
    this.resolvedAt,
    this.notes,
  });

  final String id;
  final String companyId;
  final String vehicleId;
  final String? registration;
  final String? reportedByDriverId;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final int? mileageAtReport;
  final DateTime reportedAt;
  final DateTime? resolvedAt;
  final String? notes;

  factory FleetIssue.fromJson(Json json) {
    final vehicle = (json['vehicles'] as Map?)?.cast<String, dynamic>();
    return FleetIssue(
      id: json['id'].toString(),
      companyId: json['company_id'].toString(),
      vehicleId: json['vehicle_id'].toString(),
      registration: vehicle?['registration']?.toString(),
      reportedByDriverId: json['reported_by_driver_id']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      priority: json['priority']?.toString() ?? 'medium',
      status: json['status']?.toString() ?? 'open',
      mileageAtReport: (json['mileage_at_report'] as num?)?.toInt(),
      reportedAt: parseDate(json['reported_at']) ?? DateTime.now(),
      resolvedAt: parseDate(json['resolved_at']),
      notes: json['notes']?.toString(),
    );
  }
}

class Repair {
  Repair({
    required this.id,
    required this.companyId,
    required this.vehicleId,
    required this.status,
    required this.partsCost,
    required this.labourCost,
    required this.otherCost,
    this.registration,
    this.issueId,
    this.garageId,
    this.garageName,
    this.description,
    this.bookedAt,
    this.startedAt,
    this.expectedCompletionAt,
    this.completedAt,
    this.mileageIn,
    this.invoiceReference,
    this.notes,
  });

  final String id;
  final String companyId;
  final String vehicleId;
  final String? registration;
  final String? issueId;
  final String? garageId;
  final String? garageName;
  final String? description;
  final String status;
  final DateTime? bookedAt;
  final DateTime? startedAt;
  final DateTime? expectedCompletionAt;
  final DateTime? completedAt;
  final int? mileageIn;
  final double partsCost;
  final double labourCost;
  final double otherCost;
  final String? invoiceReference;
  final String? notes;

  double get totalCost => partsCost + labourCost + otherCost;

  factory Repair.fromJson(Json json) {
    final vehicle = (json['vehicles'] as Map?)?.cast<String, dynamic>();
    final garage = (json['garages'] as Map?)?.cast<String, dynamic>();
    return Repair(
      id: json['id'].toString(),
      companyId: json['company_id'].toString(),
      vehicleId: json['vehicle_id'].toString(),
      registration: vehicle?['registration']?.toString(),
      issueId: json['issue_id']?.toString(),
      garageId: json['garage_id']?.toString(),
      garageName: garage?['name']?.toString(),
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'planned',
      bookedAt: parseDate(json['booked_at']),
      startedAt: parseDate(json['started_at']),
      expectedCompletionAt: parseDate(json['expected_completion_at']),
      completedAt: parseDate(json['completed_at']),
      mileageIn: (json['mileage_in'] as num?)?.toInt(),
      partsCost: (json['parts_cost'] as num?)?.toDouble() ?? 0,
      labourCost: (json['labour_cost'] as num?)?.toDouble() ?? 0,
      otherCost: (json['other_cost'] as num?)?.toDouble() ?? 0,
      invoiceReference: json['invoice_reference']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}
