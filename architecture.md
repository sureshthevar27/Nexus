graph TB
    subgraph "Mobile Client (Flutter)"
        App[Project Nexus App]
        Discovery[Discovery & Linking]
        Dashboard[Clinical Dashboard]
        Intelligence[AI Risk Analysis]
        Share[Secure QR Share]
    end

    subgraph "National Health Gateway (Backend)"
        API[Express.js API Router]
        Auth[OTP & Session Mgmt]
        FHIR[FHIR R4 Mapper]
        Vault[Share Vault - Memory Cache]
        
        subgraph "AI Synthesis Engine"
            AISummary[Clinical Summary Agent]
            AIIntel[Intelligence Synthesis Agent]
            AISearch[Clinical Search Agent]
        end
    end

    subgraph "Decentralized Hospital Nodes (Simulated)"
        DB[(Nexus SQLite DB)]
        Apollo[Apollo Hospital Node]
        Max[Max Specialty Node]
        JSON[hospital_db.json]
    end

    subgraph "External Intelligence"
        OpenAI[OpenAI GPT-4o / gpt-4o-mini]
    end

    subgraph "Sharing Ecosystem"
        WebPortal[Doctor's Web Portal]
        QR[QR Code Generation]
    end

    %% Connections
    Discovery --> Auth
    Dashboard --> API
    API --> FHIR
    FHIR --> DB
    DB --> Apollo
    DB --> Max
    JSON -.-> DB

    API --> AISummary
    API --> AIIntel
    API --> AISearch
    
    AISummary & AIIntel & AISearch <--> OpenAI

    Share --> QR
    QR --> Vault
    Vault --> WebPortal
    
    %% Styling
    style App fill:#001B3D,color:#fff,stroke:#D4AF37,stroke-width:2px
    style DB fill:#f5f7fa,stroke:#001B3D
    style OpenAI fill:#10a37f,color:#fff
    style WebPortal fill:#F8FAFC,stroke:#001B3D,stroke-dasharray: 5 5
    style AISummary fill:#D4AF37,color:#000
