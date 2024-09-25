public class ReplicatedInstallInstructions {
    ReplicatedApplication app;
    ReplicatedCustomer customer;
    ReplicatedChannel channel;
    ReplicatedPlatform platform;

    public ReplicatedInstallInstructions(ReplicatedPlatform platform, ReplicatedApplication application, ReplicatedCustomer customer, ReplicatedChannel channel) {
        this.app = application;
        this.customer = customer;
        this.channel = channel;
        this.platform = platform;
    }

    public String appName() {
        return this.app.name;
    }

    private String helmUsername() {
        return this.customer.email;
    }

    private String helmPassword() {
        return this.customer.licenseId;
    }

    private String helmRegistryHost() {
        return this.platform.platformHostname('registry', this.app.id, this.channel.id);
    }

    private String helmVersion() {
        return '';
    }

    private String helmUri() {
        String slugFragment = '';
        
        if ( this.channel.channelSlug != 'stable' ) {
            slugFragment = '/' + this.channel.channelSlug;
        }

        return 'oci://' + helmRegistryHost() + '/' + this.app.slug + slugFragment;
    }

    private String ecDownloadHost() {
        return this.platform.platformHostname('replicatedApp', this.app.id, this.channel.id);
    }

    private String ecDownloadPath() {
        return this.app.slug + '/' + this.channel.channelSlug;
    }

    private String ecDownloadUri() {
        return 'https://' + ecDownloadHost() + '/embedded/' + ecDownloadPath() ;
    }

    private String ecTarballFilename() {
        return this.app.slug + '.tar.gz';
    }

    private String ecAuthHeader() {
        return 'Authorization: Bearer ' + this.customer.licenseId;
    }

    private String ecInstallCommand() {
        return this.app.slug;
    }

    private String ecAirgapBundle() {
        return this.app.slug + '.airgap' ;
    }

    private String kotsApp() {
        return this.app.slug;
    }

    public String embeddedClusterInstall() {
        List<String> templateLines = new List<String> {
           'To start your install, all you need a virtual machine meeting the minimum requirements in the {0} documentation. The installer will convert that virtual maching into a single node Kubernetes cluster ready to run your application, then provide an Admin Console for you to complete the install and manage the {0} application. You will be able to to expand the cluster to multiple nodes using the Admin Console.',
           '',
           '1. Run the following command to download the installer. You can run this commmand directly on the first node, or run it on a workstation and copy the downloade file onto your first node. When you add nodes, you will use the same download on each additional node server.',
           '',
            '    curl -f {1} -H {4} -o {2}',
           '',
           '2. (optional) If you downloaded to a local workstation, copy the file you downloaded onto the server that will become your first node. If you downloaded directly to the first node, you can skip this step.',
           '',
           '3. Extract the installer and license file from the archive.',
           '',
           '     tar -xzvfr {2}',
           '',
           '4. Begin the installation the application by running the following command. You will be prompted for a password for the Admin Console. Be sure to store this password securely. You will need to use it to access the console.',
           '',
           '     sudo ./{3} install --license license.yaml',
           '',
           '5. When this phase of the installation is complete, it will output a URL for the Admin Console. Open that URL in your browser to complete the installation. Note that the URL might include the private IP for the server you are installing on rather than a public IP you can access from your workstation. In this case, use the same port with the public IP/hostname.'
        };
        
        return String.format(String.join(templateLines, '\n'), new List<String> { appName(), ecDownloadUri(), ecTarballFilename(), ecInstallCommand(), ecAuthHeader() });
    }

    public String helmInstall() {
        List<String> templateLines = new List<String> {
            'You need two things to begin your {0} installation:',
            '',
            '1. A Kubernetes cluster that meets the minimum system requires from our documentation. Not to worry, our preflight checks will keep you honest and make sure your installation will succeed.',
            '2. Access to that Kubernetes cluster via the `kubectl` and `helm` commands.',
            '',
            'Run the following log into the {0} Helm registry. This will allow you to access the pre-flight checks and install the Helm chart',
            '',
            '    helm registry login {0} --username {3} --password {4}',
            '',
            'Run the pre-flight checks to validate that your Kubernets cluster and its environment meet the prerequisites for installing {0} application. You should installt the latest version of the `preflight` plugin to `kubectl` before running this command.',
            '',
            '    curl https://krew.sh/preflight | bash    # optional',
            '    helm template {1} | kubectl preflight  -',
            '',
            'If the preflights do not pass, you should resolve any failures and warnings before continuing.',
            '',
            '',
            'Once the preflights pass, install {0} using the Helm chart',
            '',
            '    helm install {1} --version {2} --'
        };
        
        return String.format(String.join(templateLines, '\n'), new List<String> { appName(), helmURI(), helmVersion(), helmUsername(), helmPassword()});
    }

    public String airgapInstall() {
        List<String> templateLines = new List<String> {
           'To start your install, all you need a virtual machine meeting the minimum requirements in the {0} documentation. The installer will convert that virtual maching into a single node Kubernetes cluster ready to run your application, then provide an Admin Console for you to complete the install and manage the {0} application. You will be able to to expand the cluster to multiple nodes using the Admin Console.',
           '',
           '1. Run the following command to download the installer. You can run this commmand directly on the first node, or run it on a workstation and copy the downloade file onto your first node. When you add nodes, you will use the same download on each additional node server.',
           '',
           '    curl -f {1}?airgap=true -H {4} -o {2}',
           '',
           '2. (optional) If you downloaded to a local workstation, copy the file you downloaded onto the server that will become your first node. If you downloaded directly to the first node, you can skip this step.',
           '',
           '3. Extract the installer and license file from the archive.',
           '',
           '     tar -xzvf {2}',
           '',
           '4. Begin the installation the application by running the following command. You will be prompted for a password for the Admin Console. Be sure to store this password securely. You will need to use it to access the console.',
           '',
           '     sudo ./{3} install --license license.yaml --airgap-bundle {5}',
           '',
           '5. When this phase of the installation is complete, it will output a URL for the Admin Console. Open that URL in your browser to complete the installation. Note that the URL might include the private IP for the server you are installing on rather than a public IP you can access from your workstation. In this case, use the same port with the public IP/hostname.'
        };
        
        return String.format(String.join(templateLines, '\n'), new List<String> { appName(), ecDownloadUri(), ecTarballFilename(), ecInstallCommand(), ecAuthHeader(), ecAirgapBundle() });
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
            '',
            '    curl https://kots.io/install | bash',
            '',
            'Once the KOTS plugin is installed, run the following command to install your application. This command will prompt you to upload your license file.',
            '',
            '    kubectl kots install {1}',
            '',
            'The installer will prompt you for a namespace and guiide you through the rest of the installation process.'
        };
        
        return String.format(String.join(templateLines, '\n'), new List<String> { appName(), kotsApp() });
    }
}
