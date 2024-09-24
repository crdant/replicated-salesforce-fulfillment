public class ReplicatedInstallInstructions {
    ReplicatedCustomer customer;

    public ReplicatedInstallInstructions(ReplicatedCustomer customer) {
        this.customer = customer;
    }

    public String embeddedClusterInstall() {
        return 'To install the embedded cluster, follow these instructions...';
    }

    public String helmInstall() {
        return 'To install with Helm, follow these instructions...';
    }

    public String kotsInstall() {
        return 'To install with KOTS, follow these instructions...';
    }
}
