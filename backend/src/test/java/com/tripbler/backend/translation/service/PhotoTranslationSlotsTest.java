package com.tripbler.backend.translation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import com.tripbler.backend.common.exception.TooManyRequestsException;

class PhotoTranslationSlotsTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
        .withUserConfiguration(PhotoTranslationSlots.class);

    @Test
    void bindsDefaults_whenPropertiesMissing() {
        runner.run(context -> {
            PhotoTranslationSlots slots = context.getBean(PhotoTranslationSlots.class);
            assertThat(slots.capacity()).isEqualTo(4);
            assertThat(slots.perUserCapacity()).isEqualTo(1);
        });
    }

    @Test
    void bindsProperties() {
        runner.withPropertyValues("translation.photo.max-concurrent=6", "translation.photo.max-concurrent-per-user=2")
            .run(context -> {
                PhotoTranslationSlots slots = context.getBean(PhotoTranslationSlots.class);
                assertThat(slots.capacity()).isEqualTo(6);
                assertThat(slots.perUserCapacity()).isEqualTo(2);
            });
    }

    @Test
    void zeroOrNegative_correctedToOne() {
        runner.withPropertyValues("translation.photo.max-concurrent=0", "translation.photo.max-concurrent-per-user=-3")
            .run(context -> {
                PhotoTranslationSlots slots = context.getBean(PhotoTranslationSlots.class);
                assertThat(slots.capacity()).isEqualTo(1);
                assertThat(slots.perUserCapacity()).isEqualTo(1);
            });
    }

    @Test
    void perUserLimit_rejectsSameUser_allowsOthers_andRemovesEntryOnClose() {
        PhotoTranslationSlots slots = new PhotoTranslationSlots(3, 1);

        PhotoTranslationSlots.Permit first = slots.acquire("a");
        assertThatThrownBy(() -> slots.acquire("a"))
            .isInstanceOfSatisfying(TooManyRequestsException.class,
                exception -> assertThat(exception.getRetryAfterSeconds()).isEqualTo(3));

        PhotoTranslationSlots.Permit other = slots.acquire("b");
        assertThat(slots.trackedUsers()).isEqualTo(2);

        first.close();
        other.close();
        assertThat(slots.trackedUsers()).isZero();
        slots.acquire("a").close();
    }

    @Test
    void globalFull_releasesUserSlotOfRejectedRequest() {
        PhotoTranslationSlots slots = new PhotoTranslationSlots(1, 1);
        PhotoTranslationSlots.Permit held = slots.acquire("a");

        assertThatThrownBy(() -> slots.acquire("b")).isInstanceOf(TooManyRequestsException.class);
        assertThat(slots.trackedUsers()).as("거절된 사용자의 자리는 남기지 않는다").isEqualTo(1);

        held.close();
        slots.acquire("b").close();
    }

    @Test
    void closeTwice_releasesOnce() {
        PhotoTranslationSlots slots = new PhotoTranslationSlots(1, 2);
        PhotoTranslationSlots.Permit permit = slots.acquire("a");
        permit.close();
        permit.close();

        // 두 번 돌려줬다면 전체 자리가 2개가 되어 아래 두 번째 acquire가 통과한다.
        PhotoTranslationSlots.Permit again = slots.acquire("a");
        assertThatThrownBy(() -> slots.acquire("b")).isInstanceOf(TooManyRequestsException.class);
        again.close();
    }
}
