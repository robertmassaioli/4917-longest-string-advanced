#include <iostream>
#include <cstdlib>
#include <stdint.h>
#include <stack>

#include "task_generator.h"

using namespace std;

int testsFailed = 0;
static const char* getTestResult(bool (*test)(void));

static bool testInitGenerator() {
   bool result = true;
   TaskGenerator* gen = new TaskGenerator();

   result &= (gen->getNextTask() == 0);
   result &= (gen->getNextTask() == 1);
   result &= (gen->getNextTask() == 2);

   delete gen;
   return result;
}

static bool testFailedTest() {
   bool result = true;
   TaskGenerator gen;

   uint32_t task = 100;
   stack<uint32_t> grabbedItems;

   task = gen.getNextTask();
   result &= task == 0;
   grabbedItems.push(task);
   task = gen.getNextTask();
   grabbedItems.push(gen.getNextTask());
   grabbedItems.push(gen.getNextTask());
   grabbedItems.push(gen.getNextTask());
   result &= grabbedItems.top() == 3;
   gen.returnFailedTask(grabbedItems.top());
   grabbedItems.pop();
   task = gen.getNextTask();
   result &= task == 3;

   return result;
}

static bool testSimpleHaveNextTask() {
   bool result = true;
   TaskGenerator gen;

   uint32_t steps = 0;
   do
   {
      gen.getNextTask();
      if(steps == 0xFFFFFF) {
         result &= gen.haveNextTask() == false;
      } else {
         result &= gen.haveNextTask() == true;
      }
      steps++;
   } while (result && steps != 0);

   return result;
}

int main(int argc, char** argv) {
   cout << "[Starting Server Tests]" << endl;

   cout << "== Running the TestGenerator tests ==" << endl;
   cout << "Running testInitGenerator()..." << getTestResult(testInitGenerator) << endl;
   cout << "Running testFailedTest()..." << getTestResult(testFailedTest) << endl;
   cout << "Running testSimpleHaveNextTask()..." << getTestResult(testSimpleHaveNextTask) << endl;
   cout << "== Finished the TestGenerator tests ==" << endl;

   if(testsFailed > 0) {
      cout << "Results: " << testsFailed << " tests failed." << endl;
   } else {
      cout << "Results: CONGRATULATIONS! All tests passed!" << endl;
   }

   cout << "[Ending Server Tests]" << endl;
   return EXIT_SUCCESS;
}

static const char* getTestResult(bool (*test)(void)) {
   if(test()) {
      return "PASSED";
   } else {
      testsFailed++;
      return "FAILED";
   }
}

