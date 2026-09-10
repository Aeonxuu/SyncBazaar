/// The reference documents shown from Settings.
///
/// Kept as data rather than widgets so the wording can be corrected without
/// touching layout, and so the same reader renders all three.
///
/// The privacy notice describes what this app actually does, checked against
/// the code rather than adapted from a template: what is written to the device,
/// what is sent to the server, and what is not collected at all. A notice that
/// does not match the software is worse than none, because it is relied upon.
library;

class InfoDocument {
  const InfoDocument({
    required this.title,
    required this.summary,
    required this.updated,
    required this.sections,
  });

  final String title;

  /// One line under the title, and the subtitle on the Settings row.
  final String summary;

  final String updated;
  final List<InfoSection> sections;
}

class InfoSection {
  const InfoSection({required this.heading, required this.body});

  final String heading;

  /// Paragraphs. A line starting with "- " is rendered as a bullet.
  final List<String> body;
}

const String _updated = '10 September 2026';

const InfoDocument privacyNotice = InfoDocument(
  title: 'Privacy notice',
  summary: 'What SyncBazaar stores, where it is kept, and what it never collects',
  updated: _updated,
  sections: [
    InfoSection(
      heading: 'In short',
      body: [
        'SyncBazaar is a point-of-sale app for running pop-up bazaars. It '
            'holds the information a stall needs to trade: your products, your '
            'bazaars, and the sales you record.',
        'It carries no advertising, no analytics, and no third-party tracking '
            'of any kind. Nothing about your business is sold or shared.',
      ],
    ),
    InfoSection(
      heading: 'What is kept on this device',
      body: [
        '- Your sign-in, so you are not asked for a password every time. '
            'Removed when you sign out.',
        '- Sales you record without a connection. These are held here, and '
            'only here, until they reach the server. They are the reason the '
            'app can keep selling with no signal.',
        '- A copy of the last information the server sent, so the app still '
            'opens and works when there is no connection. Cleared when you '
            'sign out.',
        '- QR codes you upload for a payment method.',
        '- Your store name, when there is no account to hold it.',
        '- Receipts you print, saved to this device as images.',
      ],
    ),
    InfoSection(
      heading: 'What is sent to the server',
      body: [
        'Your account details, your products and stock, your bazaars and the '
            'venues they are held at, and every sale recorded against them. '
            'This is what lets the same business use more than one device and '
            'see the same figures on each.',
        'Sales are sent as soon as there is a connection. Each one carries an '
            'identifier generated on the device so that a sale resent after a '
            'dropped connection is recognised rather than counted twice.',
        'Images you upload, such as product photos and payment QR codes, are '
            'stored with the service that hosts the app’s files.',
      ],
    ),
    InfoSection(
      heading: 'What is never collected',
      body: [
        '- Customer payment details. The app records how a customer paid and, '
            'where a method asks for one, a reference number they give you. '
            'It never sees a card number, a PIN, or a wallet balance.',
        '- Location. The app does not ask for it and does not use it.',
        '- Contacts, messages, or anything else on the device outside the app.',
        '- Any usage or behavioural tracking.',
      ],
    ),
    InfoSection(
      heading: 'Customer names on receipts',
      body: [
        'A customer name is optional. Leaving it blank records the sale as '
            '"Walk-in", and a receipt printed for that sale carries no name.',
        'If a name is entered it appears on that receipt and in your own sales '
            'history. Only enter one when the customer has given it to you for '
            'that purpose.',
      ],
    ),
    InfoSection(
      heading: 'Who can see what',
      body: [
        'Access follows the role on the account. An employee sees the bazaars '
            'they are assigned to. An owner or administrator sees everything '
            'belonging to their business.',
        'Businesses are kept apart: an account can only reach the data of the '
            'business it belongs to.',
      ],
    ),
    InfoSection(
      heading: 'Removing your data',
      body: [
        'Signing out clears your session and the stored copy of your data from '
            'the device. Sales that have not yet reached the server are kept, '
            'so that signing out does not discard takings; they are sent the '
            'next time you sign in with a connection.',
        'To have the records held on the server removed, contact whoever '
            'administers your business account.',
      ],
    ),
  ],
);

const InfoDocument termsOfUse = InfoDocument(
  title: 'Terms of use',
  summary: 'The conditions for using SyncBazaar',
  updated: _updated,
  sections: [
    InfoSection(
      heading: 'Who may use this app',
      body: [
        'SyncBazaar is provided to a business and to the people that business '
            'authorises. Accounts are issued by the owner or administrator of '
            'the business, and are personal to the individual they are issued '
            'to.',
        'Keep your sign-in to yourself. Anything done with an account is '
            'treated as done by the person it belongs to, which matters when a '
            'sale or a stock change has to be accounted for.',
      ],
    ),
    InfoSection(
      heading: 'Recording sales accurately',
      body: [
        'The app records what it is told. A sale entered against the wrong '
            'product, the wrong quantity, or the wrong payment method will be '
            'reported that way in every total that follows.',
        'A bazaar that has taken money cannot be deleted, and a bazaar that '
            'has finished is kept as a record. This is deliberate: sales are '
            'financial records, not entries to be tidied away.',
      ],
    ),
    InfoSection(
      heading: 'Working without a connection',
      body: [
        'The app is built to keep selling when there is no signal. Sales made '
            'offline are held on the device and sent when a connection '
            'returns.',
        'While offline the app shows the last information it received, and '
            'says so above the figures. Those figures may not include sales '
            'made on another device in the meantime. Treat them as this '
            'device’s view rather than as the final position.',
        'Do not uninstall the app or clear its data while sales are waiting to '
            'be sent. That is the one action that discards them.',
      ],
    ),
    InfoSection(
      heading: 'Availability',
      body: [
        'The app depends on a server for anything shared between devices. That '
            'server may be unavailable at times, for maintenance or otherwise. '
            'Selling continues offline, but figures shared across devices will '
            'not be current until it returns.',
      ],
    ),
    InfoSection(
      heading: 'Changes to these terms',
      body: [
        'These terms may be updated as the app changes. The date at the top of '
            'this page is when they were last revised.',
      ],
    ),
  ],
);

const InfoDocument frequentlyAsked = InfoDocument(
  title: 'Questions and answers',
  summary: 'Common questions about selling, syncing, and receipts',
  updated: _updated,
  sections: [
    InfoSection(
      heading: 'Can I sell without an internet connection?',
      body: [
        'Yes. Open the app at least once with a connection so it has your '
            'products and bazaars, and it will keep selling after the signal '
            'goes. Sales are held on the device and sent when it returns.',
        'You will see a line above the figures saying the app is offline and '
            'when its information was last updated.',
      ],
    ),
    InfoSection(
      heading: 'What happens to sales I make offline?',
      body: [
        'They are saved on the device straight away, including if the app is '
            'closed or the tablet restarts. Press Sync when you have a signal, '
            'or leave auto-sync on and they go by themselves.',
        'The sync message tells you what actually happened, for example "Sent '
            '3 sale(s)" or "2 still waiting for a connection".',
      ],
    ),
    InfoSection(
      heading: 'Why is the first sign-in of the day slow?',
      body: [
        'The server sleeps when nobody has used it for a while, and takes '
            'around half a minute to wake. It is not stuck. Every action after '
            'that is quick until it goes idle again.',
      ],
    ),
    InfoSection(
      heading: 'Where do printed receipts go?',
      body: [
        'On a tablet or phone, into the photo gallery, so they are one tap '
            'from the home screen. On a computer, into the Downloads folder.',
        'A receipt grows longer with the number of items, and is saved as an '
            'image you can send to a customer.',
      ],
    ),
    InfoSection(
      heading: 'Why can I not delete a bazaar?',
      body: [
        'A bazaar that has recorded sales cannot be deleted, because those '
            'sales are financial records. A bazaar that has already finished '
            'is kept for the same reason.',
        'A bazaar set up but never sold at can be deleted, and any stock '
            'allocated to it returns to the master inventory.',
      ],
    ),
    InfoSection(
      heading: 'Why does my new bazaar need approval?',
      body: [
        'A bazaar proposed by an employee waits for an owner or administrator '
            'to approve it, and appears in Pending Approvals until they do. '
            'One created by an owner or administrator goes live immediately.',
      ],
    ),
    InfoSection(
      heading: 'What does the Sync button do?',
      body: [
        'Two things, in order. It sends any sales this device is still holding, '
            'then fetches the latest information from the server.',
        'It reports what happened rather than a fixed message, so "Up to date" '
            'and "2 still waiting for a connection" mean different things.',
      ],
    ),
    InfoSection(
      heading: 'How do I take payment by QR?',
      body: [
        'Add the QR code to the payment method under Venues & Terms. Upload any '
            'picture containing the code and the app will find it, crop to it, '
            'and check it still scans.',
        'At checkout, choosing that method and pressing Finish shows the code '
            'to the customer, with a box for the reference number they give '
            'you once they have paid.',
      ],
    ),
    InfoSection(
      heading: 'The figures on two devices do not match',
      body: [
        'Pull down on the dashboard, or press Sync, on the device showing the '
            'older figures. Each device keeps its own copy until it refreshes.',
        'If one of them is offline it will say so above the figures, and those '
            'will not include sales made elsewhere.',
      ],
    ),
  ],
);

/// The order they appear in Settings: what the app does with your data, then
/// the conditions of use, then help.
const List<InfoDocument> settingsDocuments = [
  privacyNotice,
  termsOfUse,
  frequentlyAsked,
];
