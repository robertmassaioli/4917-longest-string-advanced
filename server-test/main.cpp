#include <iostream>
#include <cstdlib>

#include "task_generator.h"

using namespace std;

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

int main(int argc, char** argv) {
   cout << "[Starting Server Tests]" << endl;

   cout << "Running testInitGenerator()..." << getTestResult(testInitGenerator) << endl;

   cout << "[Ending Server Tests]" << endl;
   return EXIT_SUCCESS;
}

static const char* getTestResult(bool (*test)(void)) {
   if(test()) {
      return "PASSED";
   } else {
      return "FAILED";
   }
}

