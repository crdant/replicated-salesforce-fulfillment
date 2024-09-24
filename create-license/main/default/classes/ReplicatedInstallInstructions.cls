public class ReplicatedInstallInstructions {
    ReplicatedApplication app;
    ReplicatedCustomer customer;

    public ReplicatedInstallInstructions(ReplicatedApplication application, ReplicatedCustomer customer) {
        this.app = application;
        this.customer = customer;
    }

    public String appName() {
        return this.app.name;
    }

    public String embeddedClusterInstall() {
        return 'To install the embedded cluster, follow these instructions...';
    }

    public String helmInstall() {
        return 'To install with Helm, follow these instructions...';
    }

    public String airgapInstall() {
        return 'To install an airgapped embedded cluster, follow these instuctions...';
    }

    public String kotsInstall() {
        List<String> templateLines = new List<String> {
          'You need three things to begin your {0} installation:',
          '',
          '1. A Kubernetes cluster that meets the minimum system requires from our documentation. Not to worry, our preflight checks will keep you honest and make sure your installation will succeed.',
          '2. Access to that Kubernetes cluster via the `kubectl` command.',
          '3. Your license file. It is attached to this email. Save it to your local machine.',
          '',
          'Run the following command to begin the installation. This command will install the KOTS plugin to `kubectl`. KOTS provides an Admin Console to assist with installation and management of your application.',
           '    curl https://kots.io/install | bash',
          '',
          'Once the KOTS plugin is installed, run the following command to install your application. This command will prompt you to upload your license file.',
          '    kubectl kots install {1}',
          '',
          'The installer will prompt you for a namespace and guiide you through the rest of the installation process.'
        };
        
        return String.format(String.join(templateLines, '\n'), new List<String> { this.app.name, this.app.slug });
    }
}
