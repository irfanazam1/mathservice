package com.example.math;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/mathservice")
/**
 * Package service controller.
 */
public class MathController {
    private static Logger log = LoggerFactory.getLogger(MathController.class);
    @GetMapping(value = "/")
    public HttpEntity<String> helloMathService(){
        log.info(">>>> helloMathService");
        return ResponseEntity.ok("Hello from Math Service!");
    }

    @PostMapping(value = "/add")
    public HttpEntity<Result> add(@RequestBody Payload payload){
        log.info(">>>> add");
        Result result = new Result(payload.Var1 + payload.Var2);
        return ResponseEntity.ok(result);
    }

    @PostMapping(value = "/subtract")
    public HttpEntity<Result> subtract(@RequestBody Payload payload){
        log.info(">>>> subtract");
        Result result = new Result(payload.Var1 - payload.Var2);
        return ResponseEntity.ok(result);
    }
}
