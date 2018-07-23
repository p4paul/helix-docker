<?php
return array(
    'environment' => array(
        'hostname' => 'swarm.helix',
    ),
    'p4' => array(
        'port' => 'p4d.helix:1666',
        'user' => 'swarm',
        'password' => 'Password!',
    ),
    'mail' => array(
        'transport' => array(
            'host' => 'swarm.helix',
        ),
    ),
    'security' => array(
        'require_login' => false, // defaults to true
    ),
);
