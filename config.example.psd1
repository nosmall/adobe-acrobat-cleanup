@{
    # Nastavte na $true pro automatickou blokaci opetovne instalace Adobe Genuine Service (AGS)
    BlockAGSReinstall           = $false

    # Nastavte na $true, pokud chcete ponechat rozsireni Adobe Acrobat v Chrome / Edge
    KeepBrowserExtensions       = $false

    # Nastavte na $true, pokud chcete ponechat doplnek PDFMaker v Microsoft Office
    KeepOfficeAddins            = $false

    # Nastavte na $true POUZE pokud chcete smazat i sdilene licencni slozky (SLStore, NGL, OOBE),
    # prestoze jsou na PC nainstalovany i jine produkty Adobe (napr. Photoshop, Lightroom)
    ForceSharedLicensingCleanup = $false

    # Volitelna vlastni cesta pro logy (ponechte prazdne pro vychozi podslozku .\logs)
    LogDir                      = ''
}
