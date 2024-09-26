public class ReplicatedLicenseEntitlement {
    public String name { get; set; }
    public String value { get; set; }
    public Boolean isDefault { get; set; }

    public ReplicatedLicenseEntitlement(String name, String value) {
        this(name, value, false);
    }

    public ReplicatedLicenseEntitlement(String name, String value, Boolean isDefault) {
        this.name = name;
        this.value = value;
        this.isDefault = isDefault;
    }
}
