package com.example.math;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/mathservice")
public class MathController {
    private static Logger log = LoggerFactory.getLogger(MathController.class);
    @GetMapping(value = "/")
    public HttpEntity<String> helloMathService(){
        log.info(">>>> helloMathService");
        return ResponseEntity.ok("Hello from Math Service!");
    }

    @PostMapping(value = "/add", consumes = MediaType.APPLICATION_JSON_VALUE)
    public HttpEntity<Integer> add(@RequestBody Payload payload){
        log.info(">>>> add");
        return ResponseEntity.ok(payload.Var1 + payload.Var2);
    }

    @PostMapping(value = "/subtract", consumes = MediaType.APPLICATION_JSON_VALUE)
    public HttpEntity<Integer> subtract(@RequestBody Payload payload){
        log.info(">>>> subtract");
        return ResponseEntity.ok(payload.Var1 - payload.Var2);
    }

    @PostMapping(value = "/multiply", consumes = MediaType.APPLICATION_JSON_VALUE)
    public HttpEntity<Integer> multiply(@RequestBody Payload payload){
        log.info(">>>> subtract");
        return ResponseEntity.ok(payload.Var1 * payload.Var2);
    }
}
