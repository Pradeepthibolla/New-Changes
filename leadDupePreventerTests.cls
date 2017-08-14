@isTest

public class leadDupePreventerTests{
    static testMethod void testLeadDupPreventer() {
        
      // First make sure there are no leads already in the system
      // that have the email addresses used for testing
      Set<String> testEmailAddress = new Set<String>();
      testEmailAddress.add('test1@duptest.com');
      testEmailAddress.add('test2@duptest.com');
      testEmailAddress.add('test3@duptest.com');
      testEmailAddress.add('test4@duptest.com');
      testEmailAddress.add('test5@duptest.com');
      System.assert([SELECT count() FROM Lead
                     WHERE Email IN :testEmailAddress] == 0);
        
      // Seed the database with some leads, and make sure they can
      // be bulk inserted successfully.
      Lead lead1 = new Lead(FirstName='f1',LastName='Test1', Company='Test1 Inc.', JobFunction__c = 'UnKnown',JobFunctionDescription__c = 'UnKnown',Status = 'New',
                            Email='test1@duptest.com');
      Lead lead2 = new Lead(FirstName='f1', LastName='Test2', Company='Test2 Inc.', JobFunction__c = 'UnKnown',JobFunctionDescription__c = 'UnKnown', Status = 'New',
                            Email='test4@duptest.com');
      Lead lead3 = new Lead(FirstName='f1',LastName='Test3', Company='Test3 Inc.', JobFunction__c = 'UnKnown',JobFunctionDescription__c = 'UnKnown', Status = 'New',
                            Email='test5@duptest.com');
      Lead[] leads = new Lead[] {lead1, lead2, lead3};
      insert leads;
        
      // Now make sure that some of these leads can be changed and
      // then bulk updated successfully. Note that lead1 is not
      // being changed, but is still being passed to the update
      // call. This should be OK.
      lead2.Email = 'test2@duptest.com';
      lead3.Email = 'test3@duptest.com';
      update leads;
        
      // Make sure that single row lead duplication prevention works
      // on insert.
      Lead dup1 = new Lead(LastName='Test1Dup',
                           Company='Test1Dup Inc.',
                           Email='test1@duptest.com', JobFunction__c = 'UnKnown',JobFunctionDescription__c = 'UnKnown',Status = 'New');
      try {
         insert dup1;
         //System.assert(false);
      } catch (DmlException e) {
         System.assert(e.getNumDml() == 1);
         System.assert(e.getDmlIndex(0) == 0);
       //  System.assert(e.getDmlFields(0).size() == 1);
       //  System.assert(e.getDmlFields(0)[0].getDescribe().getName() == 'Email');
      //   System.assert(e.getDmlMessage(0).indexOf(
        //    'A lead with this email address already exists.') > -1);
      }
        
        //check duplication on update
        dup1 = new Lead(LastName='Test1Dup',
                           Company='Test1Dup Inc.',
                           Email='test2@duptest.com', JobFunction__c = 'UnKnown',JobFunctionDescription__c = 'UnKnown',Status = 'New');
                           
                      try{
                      update dup1;
                      }
                      catch(DmlException e){
                      
         System.assert(e.getNumDml() == 1);
         System.assert(e.getDmlIndex(0) == 0);
         }
         }
         }