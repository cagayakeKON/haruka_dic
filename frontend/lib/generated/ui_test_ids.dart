// GENERATED from config/ui_test_ids.json; sha256:7119b6237c1db03bca5943666d90eeda5c37a6cf777497575c63b8539893f2a5. Do not edit.
abstract final class UiTestIds {
  static const accountChangePassword = "client.account.password.submit";
  static const accountConfirmPassword = "client.account.password.confirm";
  static const accountCurrentPassword = "client.account.password.current";
  static const accountMaterials = "client.account.reference.materials";
  static const accountNavigation = "client.shell.navigation.account";
  static const accountNewPassword = "client.account.password.new";
  static const accountPage = "client.account.home.page";
  static const accountSessions = "client.account.sessions.open";
  static const accountSignOut = "client.account.home.sign_out";
  static const activationResendEmail = "client.auth.activation_resend.email";
  static const activationResendPage = "client.auth.activation_resend.page";
  static const activationResendSubmit = "client.auth.activation_resend.submit";
  static const adminLoginEmail = "admin.auth.login.email";
  static const adminLoginPage = "admin.auth.login.page";
  static const adminLoginPassword = "admin.auth.login.password";
  static const adminLoginSubmit = "admin.auth.login.submit";
  static const adminPage = "admin.shell.home.page";
  static const adminPolicyPage = "admin.auth.policy.page";
  static const adminRegistrationSave = "admin.auth.policy.save";
  static const adminRegistrationToggle = "admin.auth.policy.registration_toggle";
  static const adminSecurityPassword = "admin.account.security.password";
  static const adminSecuritySessions = "admin.account.security.sessions";
  static const adminSignOut = "admin.auth.policy.sign_out";
  static const authActionError = "client.auth.action.error";
  static const authBackLogin = "client.auth.frame.back_login";
  static const authFormError = "client.auth.form.error";
  static const authResultPage = "client.auth.result.page";
  static const backHome = "client.shell.navigation.back_home";
  static const checkConnection = "client.shell.environment.check";
  static const configurationError = "client.shell.configuration.error";
  static const connectionStatus = "client.shell.environment.status";
  static const environmentNavigation = "client.shell.navigation.environment";
  static const environmentPage = "client.shell.environment.page";
  static const fixtureConfirm = "client.fixture.controls.confirm";
  static const fixtureDialog = "client.fixture.controls.dialog";
  static const fixtureInput = "client.fixture.controls.input";
  static const fixtureLastRow = "client.fixture.controls.last";
  static const fixtureList = "client.fixture.controls.list";
  static const fixtureNavigate = "client.fixture.controls.navigate";
  static const fixturePage = "client.fixture.controls.page";
  static const fixtureSubmit = "client.fixture.controls.submit";
  static const homeNavigation = "client.shell.navigation.home";
  static const homePage = "client.shell.home.page";
  static const loginEmail = "client.auth.login.email";
  static const loginPage = "client.auth.login.page";
  static const loginPassword = "client.auth.login.password";
  static const loginRecoveryLink = "client.auth.login.recovery_link";
  static const loginRegisterLink = "client.auth.login.register_link";
  static const loginSubmit = "client.auth.login.submit";
  static const notFoundPage = "client.shell.not_found.page";
  static const recoveryAcceptedResetLink = "client.auth.result.reset_link";
  static const recoveryCompleteConfirm = "client.auth.recovery_complete.confirm";
  static const recoveryCompletePage = "client.auth.recovery_complete.page";
  static const recoveryCompletePassword = "client.auth.recovery_complete.password";
  static const recoveryCompleteSubmit = "client.auth.recovery_complete.submit";
  static const recoveryCompleteToken = "client.auth.recovery_complete.token";
  static const recoveryRequestEmail = "client.auth.recovery_request.email";
  static const recoveryRequestPage = "client.auth.recovery_request.page";
  static const recoveryRequestSubmit = "client.auth.recovery_request.submit";
  static const referenceBackAccount = "client.reference.navigation.account";
  static const referenceCollectionsLoaded = "client.reference.collections.loaded";
  static const referenceCollectionsNav = "client.shell.reference.collections";
  static const referenceCollectionsPage = "client.reference.collections.page";
  static const referenceErrorState = "client.reference.flow.error_state";
  static const referenceMaterialsNav = "client.shell.reference.materials";
  static const referenceMaterialsPage = "client.reference.materials.page";
  static const referenceOpenCollections = "client.reference.collections.open";
  static const referenceQuery = "client.reference.selection.query";
  static const referenceSave = "client.reference.collection.save";
  static const referenceSavedState = "client.reference.collection.saved_state";
  static const registerConfirm = "client.auth.register.confirm";
  static const registerEmail = "client.auth.register.email";
  static const registerPage = "client.auth.register.page";
  static const registerPassword = "client.auth.register.password";
  static const registerSubmit = "client.auth.register.submit";
  static const registrationAcceptedVerifyLink = "client.auth.result.verify_link";
  static const sessionRevokeAll = "client.account.sessions.revoke_all";
  static const settingsAvatarDelete = "client.settings.avatar.delete";
  static const settingsAvatarReplace = "client.settings.avatar.replace";
  static const settingsCacheClear = "client.settings.cache.clear";
  static const settingsGuideSave = "client.settings.guide.save";
  static const settingsGuideSkip = "client.settings.guide.skip";
  static const settingsProfileSave = "client.settings.profile.save";
  static const settingsServiceConfirm = "client.settings.service.confirm";
  static const settingsServiceProbe = "client.settings.service.probe";
  static const verificationPage = "client.auth.verification.page";
  static const verificationSubmit = "client.auth.verification.submit";
  static const verificationToken = "client.auth.verification.token";
  static String referenceBlock(String blockId) {
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(blockId)) {
      throw ArgumentError.value(blockId, "blockId", 'Expected UUID');
    }
    return "client.reference.chapter.block." + blockId.toLowerCase();
  }

  static String referenceCollectionRow(String collectionId) {
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(collectionId)) {
      throw ArgumentError.value(collectionId, "collectionId", 'Expected UUID');
    }
    return "client.reference.collections.row." + collectionId.toLowerCase();
  }

  static String referenceMaterialRow(String materialId) {
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(materialId)) {
      throw ArgumentError.value(materialId, "materialId", 'Expected UUID');
    }
    return "client.reference.materials.row." + materialId.toLowerCase();
  }

  static String sessionRevoke(String sessionId) {
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(sessionId)) {
      throw ArgumentError.value(sessionId, "sessionId", 'Expected UUID');
    }
    return "client.account.sessions.revoke." + sessionId.toLowerCase();
  }
}
