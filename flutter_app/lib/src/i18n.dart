// Interface text in every supported language, side by side, plus money
// formatting for the chosen currency. To add a language: add its code to
// [languages], a column to [S._t], and month/weekday names in logic.dart.

import 'package:intl/intl.dart';

import 'backend.dart';

const languages = {'pt': 'Português', 'en': 'English'};

/// Currencies with two decimal places (amounts are stored in cents).
const currencies = {
  'EUR': ('Euro', 'Euro'),
  'USD': ('Dólar americano', 'US dollar'),
  'GBP': ('Libra esterlina', 'British pound'),
  'BRL': ('Real brasileiro', 'Brazilian real'),
  'CHF': ('Franco suíço', 'Swiss franc'),
  'CAD': ('Dólar canadiano', 'Canadian dollar'),
  'AUD': ('Dólar australiano', 'Australian dollar'),
  'AOA': ('Kwanza angolano', 'Angolan kwanza'),
  'MZN': ('Metical moçambicano', 'Mozambican metical'),
};

/// The language to use when the user hasn't picked one: the device's, if supported.
String resolveLanguage(String? chosen, String deviceLanguage) =>
    chosen ?? (languages.containsKey(deviceLanguage) ? deviceLanguage : 'en');

class Money {
  Money(this.language, this.currency) {
    // numbers: 'pt' writes 1.234,56, 'en' writes 1,234.56
    _number = NumberFormat.decimalPatternDigits(locale: language == 'pt' ? 'pt' : 'en', decimalDigits: 2);
    // symbol position: Portugal "12,00 €", Brazil "R$ 12,00", English "€12.00"
    final symbolLocale = language != 'pt' ? 'en' : (currency == 'BRL' ? 'pt' : 'pt_PT');
    final cur = NumberFormat.simpleCurrency(locale: symbolLocale, name: currency);
    symbol = cur.currencySymbol;
    symbolFirst = cur.format(1).trim().startsWith(symbol);
  }

  final String language, currency;
  late final NumberFormat _number;
  late final String symbol;

  /// "€1.00" (en) vs "1,00 €" (pt).
  late final bool symbolFirst;

  /// The number only, e.g. "1.234,56", "−12,00", "+5,00".
  String amount(int cents, {bool sign = false}) {
    final s = _number.format(cents.abs() / 100);
    if (cents < 0) return '−$s';
    return sign && cents > 0 ? '+$s' : s;
  }

  /// With the currency symbol in the right place, e.g. "1.234,56 €", "$1,234.56", "R$ 12,00".
  String full(int cents, {bool sign = false}) {
    final a = amount(cents, sign: sign);
    if (!symbolFirst) return '$a $symbol';
    final gap = symbol.length > 1 ? ' ' : ''; // "US$ 5", "CHF 5", but "€5", "$5"
    return '$symbol$gap$a';
  }
}

/// Reads an amount typed in any common style: "1.234,56", "1,234.56", "35", "35.5", "12,90 €".
int? parseAmount(String text) {
  final t = text.replaceAll(RegExp(r'[^\d.,]'), '');
  if (t.isEmpty) return null;
  final last = t.lastIndexOf(RegExp(r'[.,]'));
  final decimals = last < 0 ? '' : t.substring(last + 1);
  if (last >= 0 && decimals.length <= 2) {
    final whole = t.substring(0, last).replaceAll(RegExp(r'[.,]'), '');
    return int.parse(whole.isEmpty ? '0' : whole) * 100 + int.parse(decimals.padRight(2, '0'));
  }
  return int.parse(t.replaceAll(RegExp(r'[.,]'), '')) * 100;
}

const _defaultCategoriesEn = {
  'Receita': 'Income',
  'Moradia': 'Housing',
  'Alimentação': 'Food',
  'Subscrição': 'Subscriptions',
  'Crédito': 'Credit',
  'Lazer': 'Leisure',
  'Outros': 'Other',
};

class S {
  const S(this.lang);
  final String lang;

  String _t(String pt, String en) => lang == 'pt' ? pt : en;

  // ---- app & navigation ----
  String get appName => _t('Painel Financeiro', 'Finance Panel');
  String get navHome => _t('Início', 'Home');
  String get navMovements => _t('Movimentos', 'Transactions');
  String get navForecast => _t('Previsão', 'Forecast');
  String get navBills => _t('Fixas', 'Bills');
  String get newExpense => _t('Nova despesa', 'New expense');
  String get settings => _t('Ajustes', 'Settings');
  String get chooseCycle => _t('Escolher ciclo', 'Choose cycle');

  // ---- shared ----
  String get paid => _t('Pago', 'Paid');
  String get planned => _t('Previsto', 'Planned');
  String get all => _t('Todos', 'All');
  String get cancel => _t('Cancelar', 'Cancel');
  String get delete => _t('Apagar', 'Delete');
  String get close => _t('Fechar', 'Close');
  String get save => _t('Guardar', 'Save');
  String get description => _t('Descrição', 'Description');
  String get somethingWrong => _t('Algo correu mal. Tenta outra vez.', 'Something went wrong. Please try again.');
  String estado(String e) => e == 'Pago' ? paid : planned;

  /// Default categories are stored by their Portuguese names; show them translated.
  String category(String name) => lang == 'pt' ? name : (_defaultCategoriesEn[name] ?? name);

  // ---- home ----
  String get leftThisCycle => _t('Sobra do ciclo', 'Left this cycle');
  String get noMovementsInCycle => _t('Ainda sem movimentos neste ciclo', 'No transactions in this cycle yet');
  String pctOfIncome(int n) => _t('$n% da receita', '$n% of income');
  String todayIs(String day) => _t('hoje, $day', 'today, $day');
  String paidPct(int n) => _t('Pago $n%', 'Paid $n%');
  String toPayPct(int n) => _t('Por pagar $n%', 'To pay $n%');
  String get income => _t('Receitas', 'Income');
  String get expenses => _t('Despesas', 'Expenses');
  String get inAccount => _t('Em conta', 'In account');
  String get lowest => _t('Mais baixo', 'Lowest');
  String get upcoming => _t('Próximos pagamentos', 'Upcoming payments');
  String get seeAll => _t('Ver todos', 'See all');
  String get nothingToPay => _t('Nada por pagar a partir de hoje.', 'Nothing left to pay from today.');

  // ---- movements ----
  String movementCount(int n) => lang == 'pt'
      ? '$n movimento${n == 1 ? '' : 's'}'
      : '$n transaction${n == 1 ? '' : 's'}';
  String get noMovements => _t('Sem movimentos para mostrar.', 'No transactions to show.');
  String get markPlanned => _t('Marcar como previsto', 'Mark as planned');
  String get markReceived => _t('Marcar como recebido', 'Mark as received');
  String get markPaid => _t('Marcar como pago', 'Mark as paid');
  String get deleteMovementQ => _t('Apagar este movimento?', 'Delete this transaction?');

  // ---- new expense ----
  String get enterAmount => _t('Indica um valor.', 'Enter an amount.');
  String get expenseHint => _t('Ex.: Supermercado', 'E.g. Groceries');
  String get todayPrefix => _t('Hoje, ', 'Today, ');
  String get addExpense => _t('Adicionar despesa', 'Add expense');
  String get expenseAdded => _t('Despesa adicionada', 'Expense added');

  // ---- forecast ----
  String cycleCount(int n) => _t('$n ciclos', '$n cycles');
  String balanceBy(String cycle) => _t('Saldo acumulado em ${cycle.toLowerCase()}', 'Balance by $cycle');
  String get leftPerCycle => _t('Sobra por ciclo', 'Left per cycle');
  String get colCycle => _t('Ciclo', 'Cycle');
  String get colIn => _t('Entra', 'In');
  String get colOut => _t('Sai', 'Out');
  String get colLeft => _t('Sobra', 'Left');
  String get colBalance => _t('Saldo', 'Balance');

  // ---- fixed bills ----
  String get billsTitle => _t('Contas fixas', 'Fixed bills');
  String get newShort => _t('Nova', 'New');
  String get outPerMonth => _t('Sai por mês', 'Out per month');
  String get inPerMonth => _t('Entra por mês', 'In per month');
  String get noBillsYet => _t('Ainda não tens contas fixas. Começa pelo salário e pelas contas da casa:',
      'No fixed bills yet. Start with your salary and household bills:');
  String get byDayOfMonth => _t('Por dia do mês', 'By day of month');
  String billsNote(int cycles) => _t(
      'As contas fixas aparecem como previstas nos próximos $cycles ciclos. '
          'Alterar uma conta muda só os movimentos que ainda estão previstos; os já pagos ficam como estão.',
      'Fixed bills show up as planned for the next $cycles cycles. '
          'Changing a bill only updates movements that are still planned; paid ones stay as they are.');
  String get variable => _t('Variável', 'Variable');
  String until(String month) => _t('até ${month.toLowerCase()}', 'until $month');
  String get newBill => _t('Nova conta fixa', 'New fixed bill');
  String get editBill => _t('Editar conta fixa', 'Edit fixed bill');
  String get billHint => _t('Ex.: Renda', 'E.g. Rent');
  String get amount => _t('Valor', 'Amount');
  String get estimatedAmount => _t('Valor estimado', 'Estimated amount');
  String get categoryLabel => _t('Categoria', 'Category');
  String get dayOfMonth => _t('Dia do mês', 'Day of month');
  String get ends => _t('Termina', 'Ends');
  String get noEnd => _t('Sem fim', 'No end');
  String get shortMonths =>
      _t('Nos meses mais curtos conta no último dia.', 'In shorter months it falls on the last day.');
  String get variableTitle => _t('O valor muda todos os meses', 'The amount changes every month');
  String get variableSub =>
      _t('Usa uma estimativa; ajusta quando souberes o valor.', 'Use an estimate; adjust it when you know the amount.');
  String get enterDescription => _t('Indica uma descrição.', 'Enter a description.');
  String get enterAmountExample => _t('Indica um valor (ex.: 45,90).', 'Enter an amount (e.g. 45.90).');
  String get billAdded => _t('Conta fixa adicionada', 'Fixed bill added');
  String get billUpdated => _t('Conta fixa atualizada', 'Fixed bill updated');
  String get billDeleted => _t('Conta fixa apagada', 'Fixed bill deleted');
  String deleteBillQ(String name) => _t('Apagar "$name"? Os movimentos já pagos ficam; os previstos saem da previsão.',
      'Delete "$name"? Paid transactions stay; planned ones leave the forecast.');
  String get otherBill => _t('Outra', 'Other');

  /// Suggested bills: (Portuguese category key, name in this language, variable?).
  List<(String, String, bool)> get billSuggestions => [
        ('Receita', _t('Salário', 'Salary'), true),
        ('Moradia', _t('Renda', 'Rent'), false),
        ('Moradia', _t('Luz', 'Electricity'), true),
        ('Moradia', _t('Água', 'Water'), true),
        ('Moradia', 'Internet', false),
        ('Moradia', _t('Telemóvel', 'Phone'), false),
        ('Subscrição', _t('Ginásio', 'Gym'), false),
        ('Subscrição', 'Streaming', false),
      ];

  // ---- onboarding ----
  String get welcome => _t('Bem-vindo', 'Welcome');
  String get onboardingTitle => _t('Vamos preparar o teu painel', "Let's set up your panel");
  String get onboardingIntro => _t(
      'Diz-nos o que entra e sai todos os meses. Com isto a previsão fica pronta. Podes mudar tudo mais tarde.',
      'Tell us what comes in and goes out every month, and your forecast is ready. You can change all of this later.');
  String get monthStartsOn => _t('O teu mês começa no dia', 'Your month starts on day');
  String get startDayHint => _t('Normalmente o dia em que recebes o salário. Usa 1 para meses de calendário.',
      'Usually the day you get paid. Use 1 for calendar months.');
  String get add => _t('Adicionar', 'Add');
  String get done => _t('Concluir', 'Done');
  String get skipForNow => _t('Saltar por agora', 'Skip for now');

  // ---- settings ----
  String get account => _t('Conta', 'Account');
  String get synced => _t('Sincronizado · cifrado de ponta a ponta', 'Synced · end-to-end encrypted');
  String get syncing => _t('A sincronizar…', 'Syncing…');
  String get offline => _t('Sem ligação — as alterações ficam guardadas aqui e sobem depois',
      'Offline — changes are kept here and upload later');
  String get signOut => _t('Terminar sessão', 'Sign out');
  String get signOutSub =>
      _t('Os dados saem deste dispositivo e ficam na tua conta', 'Your data leaves this device and stays in your account');
  String get deleteAccount => _t('Apagar conta', 'Delete account');
  String get deleteAccountSub =>
      _t('Apaga a conta e todos os dados no servidor, para sempre', 'Deletes the account and all its data, for good');
  String get deleteAccountQ => _t('Apagar a conta e todos os dados? Não é possível desfazer.',
      'Delete the account and all its data? This cannot be undone.');
  String get createOrSignIn => _t('Criar conta ou entrar', 'Create an account or sign in');
  String get createOrSignInSub =>
      _t('Para ter os dados em vários dispositivos, cifrados', 'To have your data on several devices, encrypted');
  String get preferences => _t('Preferências', 'Preferences');
  String get language => _t('Idioma', 'Language');
  String get automatic => _t('Automático', 'Automatic');
  String get currency => _t('Moeda', 'Currency');
  String currencyName(String code) => '${lang == 'pt' ? currencies[code]!.$1 : currencies[code]!.$2} ($code)';
  String get data => _t('Dados', 'Data');
  String get startDay => _t('Dia de início do ciclo', 'Cycle start day');
  String startDaySub(int d) => _t('Os ciclos começam no dia $d', 'Cycles start on day $d');
  String get exportData => _t('Exportar dados', 'Export data');
  String get exportSub => _t('Copia uma cópia (JSON) para a área de transferência', 'Copies a backup (JSON) to the clipboard');
  String get exported => _t('Cópia copiada', 'Backup copied');
  String get importData => _t('Importar dados', 'Import data');
  String get importSub => _t('Cola uma cópia exportada antes (também do painel web)', 'Paste a backup exported before');
  String get pasteHint => _t('Cola aqui o JSON exportado', 'Paste the exported JSON here');
  String get importAction => _t('Importar', 'Import');
  String get imported => _t('Dados importados', 'Data imported');
  String get invalidBackup => _t('Ficheiro inválido', 'Invalid backup');
  String get resetData => _t('Repor dados de exemplo', 'Reset to example data');
  String get resetSub => _t('Apaga os teus movimentos e volta ao início', 'Deletes your transactions and starts over');
  String get resetQ => _t('Repor os dados de exemplo? Os teus movimentos serão apagados.',
      'Reset to the example data? Your transactions will be deleted.');
  String get resetAction => _t('Repor', 'Reset');
  String get resetDone => _t('Dados repostos', 'Data reset');
  String get privacySignedIn => _t(
      'Os dados são cifrados neste dispositivo antes de irem para o servidor. '
          'Só tu os consegues ler, com a tua palavra-passe ou a chave de recuperação.',
      'Your data is encrypted on this device before it goes to the server. '
          'Only you can read it, with your password or your recovery key.');
  String get privacyLocal => _t(
      'Os dados ficam só neste dispositivo e nunca são enviados para nenhum servidor. Exporta uma cópia de vez em quando.',
      'Your data stays on this device only and is never sent to any server. Export a backup now and then.');

  // ---- account screens ----
  String get signIn => _t('Entrar', 'Sign in');
  String get createAccount => _t('Criar conta', 'Create account');
  String get recoverAccess => _t('Recuperar acesso', 'Recover access');
  String get sendEmail => _t('Enviar email', 'Send email');
  String get privacyBlurb => _t(
      'Os teus dados são cifrados neste dispositivo antes de serem enviados. Ninguém — nem quem gere o servidor — os consegue ler.',
      'Your data is encrypted on this device before it is sent. Nobody — not even whoever runs the server — can read it.');
  String get email => 'Email';
  String get password => _t('Palavra-passe', 'Password');
  String atLeastChars(int n) => _t('Pelo menos $n caracteres', 'At least $n characters');
  String get repeatPassword => _t('Repetir palavra-passe', 'Repeat password');
  String get show => _t('Mostrar', 'Show');
  String get hide => _t('Esconder', 'Hide');
  String get enterEmail => _t('Indica o teu email.', 'Enter your email.');
  String get passwordsDontMatch => _t('As palavras-passe não coincidem.', "The passwords don't match.");
  String get enterPassword => _t('Indica a palavra-passe.', 'Enter your password.');
  String confirmEmailSent(String email) => _t(
      'Enviámos um email para $email. Abre a ligação para confirmar a conta e depois entra aqui.',
      'We sent an email to $email. Open the link to confirm your account, then sign in here.');
  String get resetEmailSent => _t(
      'Se existir uma conta com este email, vais receber uma ligação para definir uma nova palavra-passe. '
          'Vais precisar da tua chave de recuperação.',
      "If there's an account with this email, you'll get a link to set a new password. "
          "You'll need your recovery key.");
  String get securingKey =>
      _t('A proteger a tua chave… pode demorar uns segundos.', 'Securing your key… this can take a few seconds.');
  String get noAccountYet => _t('Ainda não tenho conta — criar conta', "I don't have an account — create one");
  String get forgotPassword => _t('Esqueci-me da palavra-passe', 'I forgot my password');
  String get haveAccount => _t('Já tenho conta — entrar', 'I have an account — sign in');
  String get continueAsGuest =>
      _t('Continuar sem conta (dados só neste dispositivo)', 'Continue without an account (data on this device only)');
  String get lastStep => _t('Último passo', 'Last step');
  String get recoveryKeyTitle => _t('A tua chave de recuperação', 'Your recovery key');
  String get recoveryKeyIntro => _t(
      'Se te esqueceres da palavra-passe, esta chave é a única forma de voltares a ver os teus dados. '
          'Nem nós a temos. Guarda-a num gestor de palavras-passe ou escreve-a em papel.',
      'If you forget your password, this key is the only way back to your data. '
          "Not even we have it. Keep it in a password manager or write it on paper.");
  String get copy => _t('Copiar', 'Copy');
  String get keyCopied => _t('Chave copiada', 'Key copied');
  String get savedKey => _t('Guardei a chave num sítio seguro', 'I saved the key somewhere safe');
  String get keepDeviceData => _t('Levar os dados deste dispositivo para a conta', "Bring this device's data into the account");
  String get keepDeviceDataSub => _t('Se não, a conta começa vazia.', 'Otherwise the account starts empty.');
  String get continueAction => _t('Continuar', 'Continue');
  String get newPassword => _t('Nova palavra-passe', 'New password');
  String get recoveryIntro => _t(
      'Para desbloquear os teus dados com uma nova palavra-passe, indica a chave de recuperação que guardaste ao criar a conta.',
      'To unlock your data with a new password, enter the recovery key you saved when you created the account.');
  String get recoveryKey => _t('Chave de recuperação', 'Recovery key');
  String get saveAndSignIn => _t('Guardar e entrar', 'Save and sign in');
  String get syncConflict => _t(
      'Os dados foram alterados noutro dispositivo. A tua última alteração aqui não foi guardada.',
      'Your data was changed on another device. Your last change here was not saved.');

  String error(BackendError e) => switch (e.code) {
        ErrorCode.invalidCredentials => _t('Email ou palavra-passe errados.', 'Wrong email or password.'),
        ErrorCode.emailNotConfirmed =>
          _t('Confirma primeiro o teu email (vê a caixa de entrada).', 'Confirm your email first (check your inbox).'),
        ErrorCode.emailExists => _t('Já existe uma conta com este email. Entra em vez de criar.',
            'There is already an account with this email. Sign in instead.'),
        ErrorCode.rateLimited =>
          _t('Demasiados pedidos. Espera uns minutos e tenta outra vez.', 'Too many requests. Wait a few minutes and try again.'),
        ErrorCode.invalidEmail => _t('Email inválido.', 'Invalid email.'),
        ErrorCode.offline =>
          _t('Sem ligação. Verifica a internet e tenta outra vez.', 'No connection. Check your internet and try again.'),
        ErrorCode.server => _t('Erro no servidor (${e.detail}).', 'Server error (${e.detail}).'),
        ErrorCode.unavailable => _t('Contas indisponíveis nesta versão.', 'Accounts are not available in this version.'),
        ErrorCode.unlockFailed =>
          _t('Não foi possível desbloquear os dados desta conta.', "Couldn't unlock this account's data."),
        ErrorCode.linkExpired =>
          _t('A ligação expirou. Pede outro email de recuperação.', 'The link has expired. Ask for another recovery email.'),
        ErrorCode.wrongRecoveryKey => _t('Chave de recuperação errada.', 'Wrong recovery key.'),
        ErrorCode.invalidRecoveryKey => _t('Chave de recuperação inválida.', 'Invalid recovery key.'),
        ErrorCode.shortPassword => atLeastChars(e.min ?? 10),
        ErrorCode.other => e.detail ?? somethingWrong,
      };
}
