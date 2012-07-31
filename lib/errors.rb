module RequiresApproval
  
  class CustomError < StandardError; end;

  class InvalidFieldsError < CustomError; end;

  class DenyingNeverApprovedError < CustomError; end;

  class PartialApprovalForNewObject < CustomError; end;

end