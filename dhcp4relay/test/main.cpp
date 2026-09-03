#include "gtest/gtest.h"
#include "mock_relay.h"
#include <string>

int main(int argc, char* argv[])
{

    testing::InitGoogleTest(&argc, argv);
    m_config = {};
    m_config.host_mac_addr = "12:32:54:24:95:36";
    if (!initialize_local_remote_id()) {
        return 1;
    }
    return RUN_ALL_TESTS();
}
