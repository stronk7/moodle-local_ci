<?php // Behat supported profiles.

global $CFG;

$CFG->behat_config = array(

    // ---------------------------------
    //     PhantomJS Web Driver
    // ---------------------------------

    // With PhantomJS headless browser (js) and Goutte headless browser (nonjs).
    'phantomjswd' => array(
        'filters' => array(
            // Some tags not working for this driver. Applied by default.
            'tags' => '~@_file_upload&&~@_alert&&~@_bug_phantomjs',
        ),
        'extensions' => array(
            'Behat\MinkExtension\Extension' => array(
                'default_session' => 'goutte',
                'goutte' => null,
                'javascript_session' => 'selenium2',
                'selenium2' => array( // Note: "selenium2" is just an alias for "webdriver" (any implementation).
                    'browser' => 'phantomjs',
                    'capabilities' => array(
                    ),
                )
            )
        )
    ),

    // ---------------------------------
    //     Selenium Web Driver
    // ---------------------------------

    // With PhantomJS headless browser (js) and Goutte headless browser (nonjs).
    'seleniumphantomjs' => array(
        'filters' => array(
            // Some tags not working for this driver. Applied by default.
            'tags' => '~@_file_upload&&~@_alert&&~@_bug_phantomjs&&@mod_glossary',
        ),
        'extensions' => array(
            'Behat\MinkExtension\Extension' => array(
                'default_session' => 'goutte',
                'goutte' => null,
                'javascript_session' => 'selenium2',
                'selenium2' => array(
                    'browser' => 'phantomjs',
                    'capabilities' => array(
                    )
                )
            )
        )
    ),
);
