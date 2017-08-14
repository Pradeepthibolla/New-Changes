/**********************************************************************************
        Author: NTT Data Americas
        Purpose: TRIGGER HANDLER FOR LEADS
                BEFORE INSERT: FUTURE CALL TO DATA.COM FOR CLEANING LEADS
                AFTER INSERT: IF CONVERTED, UPDATES TRAINING REQUESTS WITH CONTACT, OPPORTUNITY AND ACCOUNT
                            ASSIGNS LEAD BASED ON CUSTOM LOGIC
        TEST CLASS: LeadTriggerHandler_Test
                
        1.0 - NANDA TUMURUGOTI - March 2016
***********************************************************************************/

public class LeadTriggerHandler{
    
    public static void executeAfterInsert(List<Lead> newList,map<Id,Lead> newMap) {
        // RUN LEAD ASSIGNMENTS
        assignLead(newList);
        // FUTURE CALL TO QUERY DATA.COM OBJECTS
        Set<Id> setCleanLeadIds = new Set<Id>();
        for(Lead l : newList){
            if(l.CleanStatus != 'Matched')
            setCleanLeadIds.add(l.Id);
        }
        if(setCleanLeadIds.size()>0)
        cleanLeadDataDotCom(newMap.keyset());
        
    }

    public static void executeAfterUpdate(List<Lead> newList,map<Id,Lead> oldMap) {
        // UPDATE TRAINING INTEREST WHEN LEAD IS CONVERTED
        convertTrainingInterest(newList,oldMap);
        list<Lead> listLead = new list<Lead>();
        // RUN LEAD ASSIGNMENTS
        for(Lead ld : newList){
            if(ld.Company != oldMap.get(ld.Id).Company || ld.Account__c != oldMap.get(ld.Id).Account__c || ld.CleanStatus != oldMap.get(ld.Id).CleanStatus){
                listLead.add(ld);
            }
        }
        if(listLead.size()>0)
        assignLead(newList);
    }
    
    public static void executeBeforeUpdate(List<Lead> newList,map<Id,Lead> oldMap) {
        // UPDATE ACCOUNT__C LOOKUP
        updateAccountLookup(newList,oldMap);
    }
    
    public static void updateAccountLookup(List<Lead> newList,map<Id,Lead> oldMap) {
        set<string> setCompanyName = new set<string>();
        set<string> setDataDotComKey = new set<string>();
        for(Lead ld : newList){
            if(ld.CleanStatus != oldMap.get(ld.Id).CleanStatus){
                setCompanyName.add(ld.Company);
                if(ld.Jigsaw != Null && ld.Jigsaw != '') {
                    setDataDotComKey.add(ld.Jigsaw);    
                }                
            }
        }
        system.debug(setDataDotComKey);
        system.debug(setCompanyName);        
        if(setDataDotComKey.size() > 0) {
            map<string,Id> mapDunsNumberAccount = new map<string,Id>();
            for(Account acc : [SELECT Id,Name,Jigsaw FROM Account WHERE Jigsaw IN :setDataDotComKey OR Name IN :setCompanyName]){
                mapDunsNumberAccount.put(acc.Jigsaw,acc.Id);
            }
            for(Lead ld : newList){
                if(ld.CleanStatus != oldMap.get(ld.Id).CleanStatus){
                    if(ld.Jigsaw != null && mapDunsNumberAccount.get(ld.Jigsaw) != null){
                        ld.Account__c = mapDunsNumberAccount.get(ld.Jigsaw);
                    }
                }
            }    
        }        
    }
    public static void assignLead(List<Lead> newList) {
        set<Id> setLeadIds = new set<Id>();
        list<Lead> listLeadUpdate = new list<Lead>();
        map<string,Account> mapAccountName = new map<string,Account>();
        map<Id,Id> mapAccountRep = new map<Id,Id>();
        // GET DEFAULT OWNERS
        Id usOwner,intOwner,canadaOwner;
        Account_Lead_Assignment_Settings__c csLdOwner = Account_Lead_Assignment_Settings__c.getValues('Default');
        if(csLdOwner != null){
            for(User u : [SELECT Id,Name FROM User Where Name = :csLdOwner.LeadUSDefaultOwner__c OR Name = :csLdOwner.LeadCanadaDefaultOwner__c OR Name = :csLdOwner.LeadInternationalDefaultOwner__c]){
                if(u.Name == csLdOwner.LeadUSDefaultOwner__c)
                usOwner = u.Id;
                if(u.Name == csLdOwner.LeadInternationalDefaultOwner__c)
                intOwner = u.Id;
                if(u.Name == csLdOwner.LeadCanadaDefaultOwner__c)
                canadaOwner = u.Id;
            }
        }
        set<string> setAcctName = new set<string>();
        set<string> setAcctCountry = new set<string>();        
        
        for(Lead ld : newList){
            setLeadIds.add(ld.id);
            setAcctName.add(ld.Company);
            setAcctCountry.add(ld.Country);
        }
        
        
        list<Account_and_Lead_Assignment__c> listAssignments_Account = new list<Account_and_Lead_Assignment__c>([SELECT Id,Country__c,Segment__c,Region__c,Territory__c,ChannelTiers__c,
        AccountInsideSalesRepAssignment__c,LeadSalesRepAssignment_1__c,LeadSalesRepAssignment_2__c,CompanyName__c,Zip_End__c,Zip_Start__c 
        FROM Account_and_Lead_Assignment__c WHERE AssignmentType__c = 'Account' AND CompanyName__c IN:setAcctName AND Country__c IN :setAcctCountry]);
        list<Account_and_Lead_Assignment__c> listAssignments_Geo = new list<Account_and_Lead_Assignment__c>([SELECT Id,Country__c,Segment__c,Region__c,Territory__c,Zip_End__c,Zip_Start__c,ChannelTiers__c,
        AccountInsideSalesRepAssignment__c,AccountClientSolutionDirector__c,AccountManagerAssignment__c,
        AccountOwnerAssignment__c,LeadSalesRepAssignment_1__c,LeadSalesRepAssignment_2__c
        FROM Account_and_Lead_Assignment__c WHERE AssignmentType__c = 'Geographic' AND Country__c IN: setAcctCountry  ]);
        // GATHER DEFAULT COMPANY ASSIGNMENTS (ZIPs ARE BLANK)
        map<string,Account_and_Lead_Assignment__c> mapDefaultAssignments = new map<string,Account_and_Lead_Assignment__c >();
        for(Account_and_Lead_Assignment__c assign : listAssignments_Account){
            if(string.isEmpty(assign.Zip_End__c) && string.isEmpty(assign.Zip_Start__c) && assign.CompanyName__c != null){
                mapDefaultAssignments.put(assign.CompanyName__c.toUpperCase() + '-' + assign.Country__c.toUpperCase(),assign);
            }
        }
        // CHECK FOR ASSIGNMENTS
        for(Lead ld : [SELECT Company,Account__c,OwnerId,PostalCode,Country,Country__c,Segment__c,SalesRegion__c,Territory__c FROM Lead WHERE Id IN :setLeadIds]){
            Account_and_Lead_Assignment__c match;
            string leadZip;
            system.debug('ld.Country');
            if(ld.Country != null){
                // CLEAN ZIP CODE
                if(ld.PostalCode != null){
                    leadZip = ld.PostalCode.ReplaceAll('-','');
                    leadZip = leadZip.ReplaceAll(' ','');
                    leadZip = leadZip.toUpperCase();
                }
                // ASSIGNMENTS USING COMPANY NAME
                for(Account_and_Lead_Assignment__c a : listAssignments_Account){
                    if(ld.Company != null && ld.Company.toUpperCase() == a.CompanyName__c.toUpperCase()){
                        system.debug(ld);
                        system.debug(a);
                        if(ld.Country != 'US' && ld.Country != 'CA' ){
                            if(mapDefaultAssignments.get(ld.Company.toUpperCase() + '-' + ld.Country.toUpperCase()) != null){
                                match = mapDefaultAssignments.get(ld.Company.toUpperCase() + '-' + ld.Country.toUpperCase());
                                break;
                            }
                            else{
                                break;
                            }
                        }
                        else if(a.Zip_Start__c != null && a.Zip_End__c != null && a.Country__c != null){
                            string zipStart = a.Zip_Start__c.ReplaceAll('-','');
                            zipStart = zipStart.ReplaceAll(' ','');   
                            zipStart = zipStart.toUpperCase();
                            String zipEnd  = a.Zip_End__c.ReplaceAll('-','');
                            zipEnd  = zipEnd.ReplaceAll(' ','');
                            zipEnd  = zipEnd.toUpperCase();
                            if(leadZip.compareTo(zipStart) >= 0 && leadZip.compareTo(zipEnd) <=0 && ld.Country == a.Country__c){
                                match = a;
                                break;
                            }
                        }
                    }
                }
                // COMPANY NAME & ZIP & COUNTRY FAILED ASSIGN DEFAULT
                if(match== null && mapDefaultAssignments.get(ld.Company.toUpperCase() + '-' + ld.Country.toUpperCase()) != null){
                    match = mapDefaultAssignments.get(ld.Company.toUpperCase() + '-' + ld.Country.toUpperCase());
                }
                system.debug(match);
                
                if(match == null && (ld.Country == 'US' || ld.Country == 'CA')){
                    // ASSIGN BY GEO
                    for(Account_and_Lead_Assignment__c a : listAssignments_Geo){
                        system.debug(a.Id + ':' + leadZip + ':' + a.Zip_Start__c + ':' + a.Zip_End__c);
                        if(leadZip == null){
                            match = a;
                            break;
                        }
                        else if(a.Zip_Start__c != null || a.Zip_End__c != null){
                            string zipStart = a.Zip_Start__c.ReplaceAll('-','');
                            zipStart = zipStart.ReplaceAll(' ','');   
                            zipStart = zipStart.toUpperCase();
                            String zipEnd  = a.Zip_End__c.ReplaceAll('-','');
                            zipEnd  = zipEnd.ReplaceAll(' ','');
                            zipEnd  = zipEnd.toUpperCase();
                            if(leadZip.compareTo(zipStart) >= 0 && leadZip.compareTo(zipEnd) <=0 && ld.Country  == a.Country__c){
                                match = a;
                                break;
                            }
                        }
                    }
                }
                system.debug(match);
                if(match != null){
                    if(match.LeadSalesRepAssignment_1__c != null)
                    ld.OwnerId = match.LeadSalesRepAssignment_1__c;
                    ld.Segment__c = match.Segment__c;
                    if(match.Segment__c != null && match.Segment__c == 'Channel')
                    ld.ChannelTiers__c = match.ChannelTiers__c;
                    ld.Country__c = match.Country__c;
                    ld.SalesRegion__c = match.Region__c;                    
                    ld.Territory__c = match.Territory__c;
                    listLeadUpdate.add(ld);
                }
                else{
                    if(ld.Country != 'US' && usOwner != null ){
                        ld.OwnerId = usOwner;
                        listLeadUpdate.add(ld);
                    }
                    else if(ld.Country != 'CA' && canadaOwner != null ){
                        ld.OwnerId = canadaOwner;
                        listLeadUpdate.add(ld);
                    }
                    else if(ld.Country != 'US' && ld.Country != 'CA' &&  intOwner != null ){
                        ld.OwnerId = intOwner;
                        listLeadUpdate.add(ld);
                    }
                }
            }
        }  
        if(listLeadUpdate.size()>0){
            Database.SaveResult[] results = Database.update(listLeadUpdate,false);
        }
        
    }
    
    @future
    public static void cleanLeadDataDotCom(set<Id> listIds){
        list<Lead> newList = new list<Lead>([SELECT Id,FirstName,Jigsaw,LastName,Company,Title,CleanStatus,Email,Phone,AnnualRevenue,CompanyDunsNumber,Industry,NumberOfEmployees,Street,State,PostalCode,Country FROM Lead WHERE Id IN: listIds]);
        // Gather details for Data.com Contact Search
        list<string> setCompanyName = new list<string>();
        list<string> setLastName = new list<string>();
        list<string> setFirstName = new list<string>();
        list<string> setEmail = new list<string>();
        set<string> setCompanyId = new set<string>();
        map<Id,DataCloudContact> mapLeadDataContact = new map<Id,DataCloudContact>();
        map<string,DataCloudCompany> mapCompany = new map<string,DataCloudCompany>();
        list<Lead> listLeadUpdate = new list<Lead>();
        for(Lead ld : newList){
            setLastName.add(ld.LastName);
            setCompanyName.add(ld.Company);
            if(ld.FirstName != null){
                setFirstName.add(ld.FirstName);
            }
            if(ld.Email != null){
                setEmail.add(ld.Email);
            }
        }
        
        // Query DataCloudContact (data.com)
        list<DataCloudContact> listDataCon = new list<DataCloudContact>([SELECT ID,FirstName,LastName,CompanyName,Title,CompanyId,Email,Phone 
        FROM DataCloudContact WHERE 
        FirstName LIKE :setFirstName AND 
        LASTName LIKE :setLastName AND 
        CompanyName LIKE :setCompanyName]);
        system.debug(listDataCon);
        for(Lead ld : newList){
            for(DataCloudContact dc : listDataCon){
                if(dc.FirstName.Contains(ld.FirstName) && dc.LastName.Contains(ld.LastName) && dc.CompanyName.Contains(ld.Company)){
                    mapLeadDataContact.put(ld.Id,dc);
                    setCompanyId.add(dc.CompanyId);
                    break;
                }
            }
        }
        system.debug(setCompanyId);
        system.debug(mapLeadDataContact);                       
        // Query DataCloudCompany (data.com)
        for(DataCloudCompany dc : [SELECT Name,AnnualRevenue,DunsNumber,Industry,NumberOfEmployees,Street,State,Zip,City,Country,CompanyId FROM DataCloudCompany WHERE CompanyId IN :setCompanyId]){
            mapCompany.put(dc.CompanyId,dc);
        }
        system.debug(mapCompany);
        for(Lead ld : newlist){
            if(mapLeadDataContact.get(ld.Id) != null){
                // STORE CONTACT FIELDS
                DataCloudContact con = mapLeadDataContact.get(ld.Id);
                ld.FirstName = con.FirstName;
                ld.LastName = con.LastName;
                ld.Title = con.Title;
                ld.Email = con.Email;
                ld.Phone = con.Phone;
                
                // STORE COMPANY FIELDS
                DataCloudCompany acc = mapCompany.get(con.CompanyId);
                ld.Company = acc.Name;
                ld.Jigsaw = acc.CompanyId;
                ld.AnnualRevenue = acc.AnnualRevenue;
                ld.CompanyDunsNumber = acc.DunsNumber;
                ld.Industry = acc.Industry;
                ld.NumberOfEmployees = acc.NumberOfEmployees;
                ld.Street = acc.Street;
                system.debug(acc.State);
                ld.PostalCode = acc.Zip;
                ld.Country = acc.Country;
                ld.City = acc.City;
                //ld.State = acc.State;
                //ld.DandbCompany = acc.Id;
                ld.CleanStatus = 'Matched';
                listLeadUpdate.add(ld);
            }
            else{
                ld.CleanStatus = 'NotFound';
                listLeadUpdate.add(ld);
            }
        }
        system.debug(listLeadUpdate);
        if(listLeadUpdate.size()>0)
        update listLeadUpdate;
    }
    
    public static void convertTrainingInterest(List<Lead> newList,map<Id,Lead> oldMap) {
        Map<Id, Lead> leadMap = new Map<Id,Lead>();
        
        for(Lead Ld : newList){
            if (Ld.IsConverted && !oldMap.get(Ld.Id).isConverted) {
                leadMap.put(Ld.Id, Ld);
            }
        }

        if( leadMap.size() > 0 ) {
            Set<Id> leadIds = leadMap.keySet();
            List<TrainingInterest__c> listTrainingInt = new List<TrainingInterest__c>([SELECT Id, Contact__c, Opportunity__c, Account__c, Lead__c FROM TrainingInterest__c WHERE Lead__c IN :leadIds]);
            list<ContactCertificates__c> listCertificates = new list<ContactCertificates__c>([SELECT Id,Lead__c,Contact__c FROM ContactCertificates__c WHERE Lead__c IN : leadIds]);
            list<ContactMembership__c> listMemberships = new list<ContactMembership__c>([SELECT Id,Lead__c,Contact__c FROM ContactMembership__c WHERE Lead__c IN : leadIds]);
            
            // UPDATE TRAINING INTEREST LOOKUP ID
            for (TrainingInterest__c child : listTrainingInt ) {
                if (leadMap.containsKey( child.Lead__c ) ) {
                    // lookup the parent lead
                    Lead parent = leadMap.get( child.Lead__c );
                    // update the fields on the child object

                    child.contact__c= parent.ConvertedContactId;
                    child.opportunity__c = parent.ConvertedOpportunityId;
                    child.account__c = parent.ConvertedAccountId;
                }
            }
            
            for(ContactCertificates__c cc : listCertificates){
                cc.Contact__c = leadMap.get(cc.Lead__c ).ConvertedContactId;
            }
            
            for(ContactMembership__c cm : listMemberships){
                cm.Contact__c = leadMap.get(cm.Lead__c ).ConvertedContactId;
            }
            
            System.debug(listTrainingInt);
            
            if(listTrainingInt.size()>0)
            update listTrainingInt;
            if(listCertificates.size()>0)
            update listCertificates;
            if(listMemberships.size()>0)
            update listMemberships;
        }
    }
    
    public static void TranslateCountryToISO2(List<Lead> newRecords) {
        Set<String> fullNameAndShortNameCountrySet = CountryReferenceHelper.getFullNameAndShortNameCountrySet();
        
        Map<String, String> fullNameToShortNameCountryMap = CountryReferenceHelper.getFullNameToShortNameCountryMap();
        
        for(Lead lead : newRecords) {
            if(lead.Country != Null && lead.Country != '') {
                if(fullNameAndShortNameCountrySet.contains(lead.Country.toLowerCase())) {
                    String shortCountryName = fullNameToShortNameCountryMap.get(lead.Country.toLowerCase());
                    
                    if(shortCountryName != Null && shortCountryName != '') {
                        lead.Country = shortCountryName;
                    }
                }   
                else {
                    lead.Country.addError('The country you entered in invalid, please enter a valid 2 Character country code !!!');
                }
            }
        }
    }
    //Checking if the email already exists in the contact
    public static void LeadEmailCheckonContact(List<Lead> newRecords) {
        Set<String> leadEmailIDSet = new Set<String>();
        //If email already exists in current leads throw error message else insert the lead
        for(Lead lead : newRecords) {
            if (Lead.Email != null){
                if (leadEmailIDSet.contains(lead.Email)) {
                    lead.Email.addError('Leads trying to insert contains duplicate Email id.');
                } 
                else {
                    leadEmailIDSet.add(lead.Email);
                }
            }
            
        }
        
        list<Contact> conLst = new list<Contact>();
        Set<String> conEmailSet = new Set<String>();
        list<lead> leadLst = new list<lead>();
        Set<String> leadEmailSet = new Set<String>();
        //If email already exists in the contacts throw an error this lead already exists
        
        conLst = [Select id, email from contact where email IN : leadEmailIDSet];
        leadLst = [Select id, email from lead where email IN : leadEmailIDSet];
        
        for(Contact con : conLst){
            if(con.email != null){
                conEmailSet.add(con.email);
            }
        }
        
        for(lead l : leadLst){
            if(l.email != null){
                leadEmailSet.add(l.email);
            }
        }
        
        for(Lead lead : newRecords) {
            if (lead.Email != null){
                if(conEmailSet.size() > 0){
                    if(conEmailSet.contains(lead.Email)){
                        lead.addError('A Contact exist with the email specified on Lead');
                    }
                }
                if(leadEmailSet.size() > 0){
                    if(leadEmailSet.contains(lead.Email)){
                        lead.addError('A Lead exist with the email specified on Lead');
                    }
                }
            }
        }
    }
}